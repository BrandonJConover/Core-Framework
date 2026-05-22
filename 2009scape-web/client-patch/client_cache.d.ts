// Glob imports for cache asset files. Resolved by the bundler (parcel/webpack)
// at build time; for tsc these need declarations so the imports type-check.
//
// TS ambient module declarations have two constraints:
//   1. Pattern can have at most ONE '*' character.
//   2. Patterns must not be relative paths (no './' or '../' prefix).
// Both are satisfied by the file-extension wildcard form below.

declare module "*.dat" {
    const value: { [key: string]: string };
    export default value;
}

declare module "*.idx" {
    const value: { [key: string]: string };
    export default value;
}

declare module "*.idx0"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx1"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx2"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx3"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx4"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx5"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx6"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx7"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx8"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx9"   { const v: { [k: string]: string }; export default v; }
declare module "*.idx10"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx11"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx12"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx13"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx14"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx15"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx16"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx17"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx18"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx19"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx20"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx21"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx22"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx23"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx24"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx25"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx26"  { const v: { [k: string]: string }; export default v; }
declare module "*.idx255" { const v: { [k: string]: string }; export default v; }

declare module "*.rs" {
    export function rs_encrypt_bytes(bytes: Int8Array | Uint8Array, modulus?: string, key?: string): Uint8Array;
    export function rs_hash_string(s: string): number;
    export function noise(x: number, y: number): number;
}
