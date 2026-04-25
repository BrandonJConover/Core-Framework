import { Buffer } from "../net/Buffer";
import { BZip2Decompressor } from "./bzip/BZip2Decompressor";
import { rs_hash_string } from "./../../wasm/src/lib.rs";

/**
 * Creates the archive.
 *
 * @param {Array} dataBuffer The buffer of the archive.
 * @class
 */
export class Archive {
  public archiveBuffer: number[];

  public dataSize: number;

  public nameHashes: number[];

  public uncompressedSizes: number[];

  public compressedSizes: number[];

  public startOffsets: number[];

  public compressed: boolean;

  public constructor(dataBuffer: number[]) {
    if (this.archiveBuffer === undefined) {
      this.archiveBuffer = null;
    }
    if (this.dataSize === undefined) {
      this.dataSize = 0;
    }
    if (this.nameHashes === undefined) {
      this.nameHashes = null;
    }
    if (this.uncompressedSizes === undefined) {
      this.uncompressedSizes = null;
    }
    if (this.compressedSizes === undefined) {
      this.compressedSizes = null;
    }
    if (this.startOffsets === undefined) {
      this.startOffsets = null;
    }
    if (this.compressed === undefined) {
      this.compressed = false;
    }
    // Tolerate missing/null data (e.g. 530-cache archive layouts where the 377
    // hardcoded archive id resolves to no/wrong data). Leave dataSize=0 so
    // getFile() returns null, which downstream parsers treat as "not present".
    if (dataBuffer == null) {
      this.archiveBuffer = [];
      this.dataSize = 0;
      this.nameHashes = [];
      this.uncompressedSizes = [];
      this.compressedSizes = [];
      this.startOffsets = [];
      return;
    }
    // Wrap the entire header+decompress in a try/catch. When we're talking to the
    // 530 cache, the bytes at a given 377 archive id are random 530 data — the 377
    // parser easily gets into a bad state and BZip2 can loop/throw.
    try {
      let buffer: Buffer = new Buffer(dataBuffer);
      const uncompressed: number = buffer.get24BitInt();
      const compressed: number = buffer.get24BitInt();
      // Sanity check: 3-byte sizes have max 0xFFFFFF; a mis-parsed archive usually
      // gives bogus huge values. Reject anything beyond what could fit in the data.
      if (uncompressed < 0 || compressed < 0 ||
          compressed > dataBuffer.length || uncompressed > 0x1000000) {
        this.archiveBuffer = [];
        this.dataSize = 0;
        this.nameHashes = [];
        this.uncompressedSizes = [];
        this.compressedSizes = [];
        this.startOffsets = [];
        return;
      }
      if (compressed !== uncompressed) {
        const data: number[] = Array(uncompressed).fill(0);
        BZip2Decompressor.decompress$byte_A$int$byte_A$int$int(
          data, uncompressed, dataBuffer, compressed, 6
        );
        this.archiveBuffer = data;
        buffer = new Buffer(this.archiveBuffer);
        this.compressed = true;
      } else {
        this.archiveBuffer = dataBuffer;
        this.compressed = false;
      }
      this.dataSize = buffer.getUnsignedLEShort();
      if (this.dataSize < 0 || this.dataSize > 10000) {
        this.archiveBuffer = [];
        this.dataSize = 0;
        this.nameHashes = [];
        this.uncompressedSizes = [];
        this.compressedSizes = [];
        this.startOffsets = [];
        return;
      }
      this.nameHashes = Array(this.dataSize).fill(0);
      this.uncompressedSizes = Array(this.dataSize).fill(0);
      this.compressedSizes = Array(this.dataSize).fill(0);
      this.startOffsets = Array(this.dataSize).fill(0);
      let offset: number = buffer.currentPosition + this.dataSize * 10;
    for (let index: number = 0; index < this.dataSize; index++) {
      {
        this.nameHashes[index] = buffer.getInt();
        this.uncompressedSizes[index] = buffer.get24BitInt();
        this.compressedSizes[index] = buffer.get24BitInt();
        this.startOffsets[index] = offset;
        offset += this.compressedSizes[index];
      }
    }
    } catch (e) {
      this.archiveBuffer = [];
      this.dataSize = 0;
      this.nameHashes = [];
      this.uncompressedSizes = [];
      this.compressedSizes = [];
      this.startOffsets = [];
    }
  }

  /**
   * Gets a file by its name.
   *
   * @param {string} file The file name.
   * @return {Array} The file contents.
   */
  public getFile(file: string): number[] {
    let dataBuffer: number[] = null;
    file = file.toUpperCase();
    const hash = rs_hash_string(file);
    for (let index: number = 0; index < this.dataSize; index++) {
      {
        if (this.nameHashes[index] === hash) {
          if (dataBuffer == null) {
            dataBuffer = Array(this.uncompressedSizes[index]).fill(0);
          }
          if (!this.compressed) {
            BZip2Decompressor.decompress$byte_A$int$byte_A$int$int(
              dataBuffer,
              this.uncompressedSizes[index],
              this.archiveBuffer,
              this.compressedSizes[index],
              this.startOffsets[index]
            );
          } else {
            for (
              let pos: number = 0;
              pos < this.uncompressedSizes[index];
              pos++
            ) {
              dataBuffer[pos] = this.archiveBuffer[
                this.startOffsets[index] + pos
              ];
            }
          }
          return dataBuffer;
        }
      }
    }
    return null;
  }
}
