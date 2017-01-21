<%@ WebHandler Language="C#" Class="export" %>

using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading.Tasks;
using System.Web;
using System.Web.Caching;
using System.Web.Script.Serialization;
using System.Xml.Serialization;

public class export : IHttpHandler {
    //
    // CONSTANTS
    //
    private const string DOWNLOAD_FOLDER = "download";
    private const double FILE_TIMEOUT = 60d; // Minutes
    //
    // METHODS
    //
    public void ProcessRequest(HttpContext context) {
        // Download JSON.
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        var reader = new StreamReader(context.Request.InputStream);
        var json = reader.ReadToEnd();
        reader.Close();

        // Deserialize JSON.
        Request request = serializer.Deserialize<Request>(json);

        // Get Download Folder.
        string download = HttpContext.Current.Server.MapPath(export.DOWNLOAD_FOLDER);
        DirectoryInfo di = new DirectoryInfo(download);
        if (!di.Exists) {
            di.Create();
        }

        // Remove old zip files (if any).
        var files = di.EnumerateFiles("*.zip").Where((f) => {
            return DateTime.Now.ToUniversalTime().Subtract(f.CreationTimeUtc).TotalMinutes > export.FILE_TIMEOUT;
        });
        foreach (var file in files) {
            if (file.Exists) {
                file.Delete();
            }
        }

        // Create Project Folder.
        string guid = Guid.NewGuid().ToString("N").ToLowerInvariant();
        DirectoryInfo project = di.CreateSubdirectory(guid);

        // Download Images
        var tasks1 = request.texture.SelectMany((tile) =>
            tile.resolution.Select((resolution) => {
                return Task.Run(() => {
                    // Assemble url
                    var url = string.Format("{0}/{1}", tile.source, "export");
                    url += string.Format("?bbox={0},{1},{2},{3}&size={4},{4}&format={5}&f=image",
                        tile.extent.xmin,
                        tile.extent.ymin,
                        tile.extent.xmax,
                        tile.extent.ymax,
                        resolution,
                        tile.format == "raw" ? "png" : tile.format
                    );

                    // Filename
                    WebClient client = new WebClient();
                    var file = string.Format("T_{0}_{1}.{2}", tile.id, resolution, tile.format);
                    var full = Path.Combine(project.FullName, file);
                    if (tile.format == "raw") {
                        var bytes = client.DownloadData(url);
                        MemoryStream stream = new MemoryStream(bytes);
                        Bitmap bitmap = new Bitmap(stream);
                        var b2 = new List<Byte>();
                        for (int y = 0; y < bitmap.Height; y++) {
                            for (int x = 0; x < bitmap.Width; x++) {
                                Color color = bitmap.GetPixel(x, bitmap.Height - y - 1);
                                b2.AddRange(new byte[] {
                                    color.R,
                                    color.G,
                                    color.B
                                });
                            }
                        }
                        bitmap.Dispose();
                        stream.Close();
                        File.WriteAllBytes(full, b2.ToArray());
                    } else {
                        client.DownloadFile(url, full);
                    }
                });
            })
        );

        // Download Elevation.
        var tasks2 = request.elevation.SelectMany((tile) =>
            tile.resolution.Select((resolution) => {
                return Task.Run(() => {
                    // Assemble url.
                    var url = string.Format("{0}/{1}", tile.source, "exportImage");
                    url += string.Format("?bbox={0},{1},{2},{3}&size={4},{4}&format={5}&token={6}&f=image",
                        tile.extent.xmin,
                        tile.extent.ymin,
                        tile.extent.xmax,
                        tile.extent.ymax,
                        resolution + 1,
                        tile.format == "raw" ? "lerc" : tile.format,
                        tile.token
                    );

                    // Filename
                    WebClient client = new WebClient();
                    var file = string.Format("E_{0}_{1}.{2}", tile.id, resolution, tile.format);
                    var full = Path.Combine(project.FullName, file);
                    if (tile.format == "raw") {
                        var bytes = client.DownloadData(url);
                        var heights = LercCodec.Decode(bytes);
                        var b2 = heights.SelectMany((h) => BitConverter.GetBytes(Convert.ToInt16(h)));
                        File.WriteAllBytes(full, b2.ToArray());
                    } else {
                        client.DownloadFile(url, full);
                    }
                });
            })
        );

        // Wait for all tasks to complete.
        var tasks = tasks1.Concat(tasks2).ToArray();
        Task.WaitAll(tasks);

        // Create Zip File.
        ZipFile.CreateFromDirectory(
            project.FullName,
            Path.Combine(di.FullName, guid + ".zip"),
            CompressionLevel.Optimal,
            false
        );
        
        // Delete project folder.
        project.Delete(true);

        // Get URL to Zip File.
        var zip = context.Request.Url.AbsoluteUri;
        int index = zip.LastIndexOf('/');
        if (index > 0) {
            zip = zip.Remove(index);
        }
        zip += string.Format("/{0}/{1}", export.DOWNLOAD_FOLDER, guid + ".zip");

        // Send Response.
        context.Response.ContentType = "application/json";
        context.Response.Write(
            serializer.Serialize(new Response() {
                url = zip
            })
        );
    }
    public bool IsReusable {
        get {
            return false;
        }
    }
}

public class Request {
    public Tile[] elevation { get; set; }
    public Tile[] texture { get; set; }
}

public class Tile {
    public int id { get; set; }
    public string source { get; set; }
    public string token { get; set; }
    public string format { get; set; }
    public int[] resolution { get; set; }
    public Extent extent { get; set; }
}

public class Extent {
    public double xmin { get; set; }
    public double ymin { get; set; }
    public double xmax { get; set; }
    public double ymax { get; set; }
}

public class Response {
    public string url { get; set; }
}

[XmlRoot("configuration")]
public class Configuration {
    private static object _lock = new object();
    public static Configuration GetConfiguration() {
        Configuration config = HttpRuntime.Cache["configuration"] as Configuration;
        if (config == null) {
            string fileName = HttpContext.Current.Server.MapPath("export.config");
            if (File.Exists(fileName)) {
                XmlSerializer reader = new XmlSerializer(typeof(Configuration));
                StreamReader file = new StreamReader(fileName);
                config = (Configuration)reader.Deserialize(file);
                file.Close();
            }
            if (config != null) {
                CacheDependency dep = new CacheDependency(fileName);
                HttpRuntime.Cache.Insert("configuration", config, dep);
            }
        }
        return config;
    }
    [XmlAttribute("setting1")]
    public string Setting1 { get; set; }
    [XmlAttribute("setting2")]
    public string Setting2 { get; set; }
}

public static class LercCodec {
    public static float[] Decode(byte[] input) {
        var options = new LercCodecOptions();
        Data parsed = LercCodec.Parse(input, options);
        float[] heights = LercCodec.UncompressPixelValues(parsed, options);
        return heights;
    }
    private static Data Parse(byte[] input, LercCodecOptions options) {
        //
        var data = new Data();

        // Header
        var fp = options.InputOffset;
        var fileIdView = new byte[10];
        data.FileIdentifierString = Encoding.UTF8.GetString(input, fp, 10).Trim();
        if (data.FileIdentifierString != "CntZImage") {
            throw new Exception(string.Format("Unexpected file identifier string: {0}", data.FileIdentifierString));
        }

        // Image dimensions
        fp += 10;
        BinaryReader b = new BinaryReader(new MemoryStream(input, fp, 24));

        data.FileVersion = b.ReadInt32();
        data.ImageType = b.ReadInt32();
        data.Height = b.ReadUInt32();
        data.Width = b.ReadUInt32();
        data.MaxZError = b.ReadDouble();
        //b.Dispose();

        // Mask Header
        fp += 24;
        //if (options.EncodedMaskData == null) {
        //MemoryStream m2 = new MemoryStream(input, fp, 16);
        //DataReader d2 = new DataReader(m2.AsInputStream()) {
        //    ByteOrder = ByteOrder.LittleEndian
        //};
        //await d2.LoadAsync(16);
        BinaryReader d2 = new BinaryReader(new MemoryStream(input, fp, 16));
        data.Mask = new Mask() {
            NumBlocksY = d2.ReadUInt32(),
            NumBlocksX = d2.ReadUInt32(),
            NumBytes = d2.ReadUInt32(),
            MaxValue = d2.ReadSingle()
        };
        //d2.Dispose();

        // Mask Data
        fp += 16;
        if (data.Mask.NumBytes > 0) {
            // **** CODE HERE ****
            throw new Exception("data.mask.numBytes > 0");
        } else if (data.Mask.NumBytes == 0 && data.Mask.NumBlocksY == 0 && data.Mask.MaxValue == 0) {
            // All no data!
            throw new Exception("data.mask.numBytes == 0");
        }
        //}

        // Pixel Header
        //MemoryStream m3 = new MemoryStream(input, fp, 16);
        //DataReader d3 = new DataReader(m3.AsInputStream()) {
        //    ByteOrder = ByteOrder.LittleEndian
        //};
        //await d3.LoadAsync(16);
        BinaryReader d3 = new BinaryReader(new MemoryStream(input, fp, 16));
        data.Pixels = new Pixels() {
            NumBlocksY = d3.ReadUInt32(),
            NumBlocksX = d3.ReadUInt32(),
            NumBytes = d3.ReadUInt32(),
            MaxValue = d3.ReadSingle()
        };
        //d3.Dispose();

        //
        fp += 16;
        var numBlocksX = data.Pixels.NumBlocksX;
        var numBlocksY = data.Pixels.NumBlocksY;
        var actualNumBlocksX = numBlocksX + ((data.Width % numBlocksX) > 0 ? 1 : 0);
        var actualNumBlocksY = numBlocksY + ((data.Height % numBlocksY) > 0 ? 1 : 0);
        data.Pixels.Blocks = new Block[actualNumBlocksX * actualNumBlocksY];
        float minValue = 1000000000;
        var blockI = 0;


        for (var blockY = 0; blockY < actualNumBlocksY; blockY++) {
            for (var blockX = 0; blockX < actualNumBlocksX; blockX++) {

                // Block
                var size = 0;
                var bytesLeft = input.Length - fp;
                //MemoryStream m4 = new MemoryStream(input, fp, Math.Min(10, bytesLeft));
                //DataReader d4 = new DataReader(m4.AsInputStream()) {
                //    ByteOrder = ByteOrder.LittleEndian
                //};
                //await d4.LoadAsync((uint)Math.Min(10, bytesLeft));
                BinaryReader d4 = new BinaryReader(new MemoryStream(input, fp, Math.Min(10, bytesLeft)));

                Block block = new Block();
                data.Pixels.Blocks[blockI++] = block;
                byte headerByte = d4.ReadByte();
                size++;
                block.Encoding = (uint)headerByte & 63;
                if (block.Encoding > 3) {
                    throw new Exception(string.Format("Invalid block encoding ({0})", block.Encoding));
                }
                if (block.Encoding == 2) {
                    fp++;
                    minValue = Math.Min(minValue, 0);
                    continue;
                }

                if ((headerByte != 0) && (headerByte != 2)) {
                    headerByte >>= 6;
                    block.OffsetType = headerByte;
                    if (headerByte == 2) {
                        block.Offset = d4.ReadByte(); //  view.getInt8(1);  ?????
                        size++;
                    } else if (headerByte == 1) {
                        block.Offset = d4.ReadInt16(); // view.getInt16(1, true);
                        size += 2;
                    } else if (headerByte == 0) {
                        block.Offset = d4.ReadSingle(); //  view.getFloat32(1, true);
                        size += 4;
                    } else {
                        throw new Exception(string.Format("Invalid block offset type"));
                    }
                    minValue = Math.Min(block.Offset, minValue);

                    if (block.Encoding == 1) {
                        headerByte = d4.ReadByte(); // view.getUint8(size);
                        size++;
                        block.BitsPerPixel = (uint)headerByte & 63;
                        headerByte >>= 6;
                        block.NumValidPixelsType = headerByte;
                        if (headerByte == 2) {
                            block.NumValidPixels = d4.ReadByte(); // view.getUint8(size);
                            size++;
                        } else if (headerByte == 1) {
                            block.NumValidPixels = d4.ReadUInt16(); // view.getUint16(size, true);
                            size += 2;
                        } else if (headerByte == 0) {
                            block.NumValidPixels = d4.ReadUInt32(); //  view.getUint32(size, true);
                            size += 4;
                        } else {
                            throw new Exception(string.Format("Invalid valid pixel count type"));
                        }
                    }
                }
                //d4.Dispose();
                fp += size;

                if (block.Encoding == 3) {
                    continue;
                }

                //var arrayBuf;
                //var store8;
                if (block.Encoding == 0) {
                    //var xxxx = "";
                    //var numPixels = (data.pixels.numBytes - 1) / 4;
                    ////if (numPixels != Math.Floor(numPixels)) {
                    ////    throw new Exception(string.Format("uncompressed block has invalid length"));
                    ////}
                    //var arrayBuf = new ArrayBuffer(numPixels * 4);

                    ////var store8 = new Uint8Array(arrayBuf);
                    ////store8.set(new Uint8Array(input, fp, numPixels * 4));

                    //var rawData = new Float32Array(arrayBuf);

                    //for (var j = 0; j < rawData.length; j++) {
                    //    minValue = Math.Min(minValue, rawData[j]);
                    //}
                    //block.rawData = rawData;
                    //fp += numPixels * 4;
                } else if (block.Encoding == 1) {
                    int dataBytes = (int)Math.Ceiling((double)block.NumValidPixels * block.BitsPerPixel / 8);
                    int dataWords = (int)Math.Ceiling((double)dataBytes / 4);

                    //int bytes = dataWords * 4;
                    //Debug.WriteLine(string.Format("{0},{1}", dataBytes, dataWords));
                    //var arrayBuf = new ArrayBuffer(dataWords * 4);
                    //var store8 = new Uint8Array(arrayBuf);
                    //store8.set(new Uint8Array(input, fp, dataBytes));
                    //block.stuffedData = new Uint32Array(arrayBuf);

                    //MemoryStream m5 = new MemoryStream(input, fp, dataBytes);
                    //DataReader d5 = new DataReader(m5.AsInputStream()) {
                    //    ByteOrder = ByteOrder.LittleEndian
                    //};
                    //await d5.LoadAsync((uint)dataBytes);
                    BinaryReader d5 = new BinaryReader(new MemoryStream(input, fp, dataBytes));

                    //var bytes = new byte[dataBytes];
                    //d5.ReadBytes(bytes);
                    var bytes = d5.ReadBytes(dataBytes);

                    //d5.Dispose();
                    if (dataWords * 4 > dataBytes) {
                        Array.Resize<byte>(ref bytes, dataWords * 4);
                    }

                    List<uint> list = new List<uint>();
                    for (var i = 0; i < dataWords; i++) {
                        list.Add(BitConverter.ToUInt32(bytes, i * 4));
                    }

                    block.StuffedData = list.ToArray();
                    fp += dataBytes;
                }
            }
        }
        data.Pixels.MinValue = minValue;
        data.EofOffset = fp;

        return data;
    }
    private static float[] UncompressPixelValues(Data data, LercCodecOptions options) {
        var blockIdx = 0;
        uint numX = data.Pixels.NumBlocksX;
        uint numY = data.Pixels.NumBlocksY;
        uint blockWidth = (uint)Math.Floor((double)data.Width / numX);
        uint blockHeight = (uint)Math.Floor((double)data.Height / numY);
        double scale = 2d * data.MaxZError;
        var resultPixels = new float[data.Width * data.Height];
        var blockDataBuffer = new float[blockWidth * blockHeight];

        //var xx, yy;
        for (var y = 0; y <= numY; y++) {
            var thisBlockHeight = (y != numY) ? blockHeight : (data.Height % numY);
            if (thisBlockHeight == 0) {
                continue;
            }
            for (var x = 0; x <= numX; x++) {
                var thisBlockWidth = (x != numX) ? blockWidth : (data.Width % numX);
                if (thisBlockWidth == 0) {
                    continue;
                }

                var outPtr = y * data.Width * blockHeight + x * blockWidth;
                var outStride = data.Width - thisBlockWidth;

                var block = data.Pixels.Blocks[blockIdx];

                //var blockData;
                var blockPtr = 0;
                float constValue = 0;
                if (block.Encoding < 2) {
                    // block is either uncompressed or bit-stuffed (encodings 0 and 1)
                    if (block.Encoding == 0) {
                        // block is uncompressed
                        //blockData = block.rawData;
                    } else {
                        // block is bit-stuffed
                        LercCodec.Unstuff(
                            block.StuffedData,
                            block.BitsPerPixel,
                            block.NumValidPixels,
                            block.Offset,
                            scale,
                            ref blockDataBuffer,
                            data.Pixels.MaxValue
                         );
                        //blockData = blockDataBuffer;
                    }
                    blockPtr = 0;
                } else if (block.Encoding == 2) {
                    // block is all 0
                    constValue = 0;
                } else {
                    // block has constant value (encoding === 3)
                    constValue = block.Offset;
                }

                // mask not present, simply copy block over
                if (block.Encoding < 2) {
                    // duplicating this code block for performance reasons
                    // blockData case:
                    for (var yy = 0; yy < thisBlockHeight; yy++) {
                        for (var xx = 0; xx < thisBlockWidth; xx++) {
                            //resultPixels[outPtr++] = blockData[blockPtr++];
                            resultPixels[outPtr++] = blockDataBuffer[blockPtr++];
                        }
                        outPtr += outStride;
                    }
                } else {
                    // constValue case:
                    for (var yy = 0; yy < thisBlockHeight; yy++) {
                        for (var xx = 0; xx < thisBlockWidth; xx++) {
                            resultPixels[outPtr++] = constValue;
                        }
                        outPtr += outStride;
                    }
                }
                //if ((block.encoding == 1) && (blockPtr != block.numValidPixels)) {
                //    throw "Block and Mask do not match";
                //}
                blockIdx++;
            }
        }

        return resultPixels;
    }
    private static void Unstuff(uint[] src, uint bitsPerPixel, uint numPixels, float offset, double scale, ref float[] dest, float maxValue) {
        int bitMask = (1 << (int)bitsPerPixel) - 1;
        int i = 0;
        //var o;
        int bitsLeft = 0;
        var n = 0;
        uint buffer = 0;
        var nmax = Math.Ceiling((maxValue - offset) / scale);
        // get rid of trailing bytes that are already part of next block
        var numInvalidTailBytes = src.Length * 4 - Math.Ceiling((double)bitsPerPixel * numPixels / 8);
        src[src.Length - 1] <<= 8 * (int)numInvalidTailBytes;

        for (var o = 0; o < numPixels; o++) {
            if (bitsLeft == 0) {
                buffer = src[i++];
                bitsLeft = 32;
            }
            if (bitsLeft >= bitsPerPixel) {
                //n = (buffer >>> (bitsLeft - bitsPerPixel)) & bitMask;
                n = ((int)buffer >> (int)(bitsLeft - bitsPerPixel)) & bitMask;
                bitsLeft -= (int)bitsPerPixel;
            } else {
                int missingBits = ((int)bitsPerPixel - bitsLeft);
                n = (((int)buffer & bitMask) << missingBits) & bitMask;
                buffer = src[i++];
                bitsLeft = 32 - missingBits;
                //n += (buffer >>> bitsLeft);
                n += ((int)buffer >> bitsLeft);
            }
            //pixel values may exceed max due to quantization
            dest[o] = n < nmax ? Convert.ToSingle(offset + n * scale) : maxValue;
        }
    }
    private class LercCodecOptions {
        public int InputOffset { get; set; }
        //public byte[] EncodedMaskData { get; set; } = null;
        public float NoDataValue { get; set; }
        //public float[] PixelType { get; set; }
        //public bool ReturnMask { get; set; } = false;
        //public bool ReturnEncodedMask { get; set; } = false;
        //public bool ReturnFileInfo { get; set; } = false;
        //public bool ComputeUsedBitDepths { get; set; } = false;
        public LercCodecOptions() {
            this.InputOffset = 0;
            this.NoDataValue = float.MinValue;
        }
    }
    private class LerceCodecResult {
        public int Width { get; set; }
        public int Height { get; set; }
        public float[] ResultPixels { get; set; }
        public float MinValue { get; set; }
        public float MaxValue { get; set; }
        public float NoDataValue { get; set; }
    }
    private class Data {
        public string FileIdentifierString { get; set; }
        public int FileVersion { get; set; }
        public int ImageType { get; set; }
        public uint Height { get; set; }
        public uint Width { get; set; }
        public double MaxZError { get; set; }
        public Mask Mask { get; set; }
        public Pixels Pixels { get; set; }
        public int EofOffset { get; set; }
    }
    private class Mask {
        public uint NumBlocksY { get; set; }
        public uint NumBlocksX { get; set; }
        public uint NumBytes { get; set; }
        public float MaxValue { get; set; }
        public byte[] Bitset { get; set; }
    }
    private class Pixels {
        public uint NumBlocksY { get; set; }
        public uint NumBlocksX { get; set; }
        public uint NumBytes { get; set; }
        public float MaxValue { get; set; }
        public float MinValue { get; set; }
        public Block[] Blocks { get; set; }
    }
    private class Block {
        public uint Encoding { get; set; }
        public uint OffsetType { get; set; }
        public float Offset { get; set; }
        public uint BitsPerPixel { get; set; }
        public uint NumValidPixelsType { get; set; }
        public uint NumValidPixels { get; set; }
        public uint[] StuffedData { get; set; }
    }
}
