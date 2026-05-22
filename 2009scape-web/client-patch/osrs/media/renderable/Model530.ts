/**
 * Model530 — bridge from RawModel530Data (rt4 idx7 byte decode) to the
 * existing 377 `Model` class so the in-tree Rasterizer3D pipeline can
 * draw rev-530 meshes without a full renderer rewrite.
 *
 * The 377 Model exposes the same logical fields the rt4 RawModel does
 * (vertices, triangle indices, per-triangle color/alpha/priority, plus
 * a textured-face PMN table), just under different names. This module
 * is purely a field-rename + lighting precompute layer; rendering /
 * culling / projection lives downstream in Rasterizer3D.
 *
 * The bridge does NOT yet:
 *   • Apply skeletal-anim transforms (Skeleton + Skin from idx0/1).
 *   • Map idx26 textures to the renderer's RGB lookup tables.
 *   • Handle complex / cube textured-face variants — those use type 1-3
 *     in RawModel530Data.textureTypes and are silently downgraded to
 *     the simple "PMN" form for now.
 *
 * Result: locs / NPCs / players draw as flat-shaded meshes with their
 * vertex-color tints. Good enough to confirm geometry is correct before
 * texture + skeleton work lands.
 */

import { Model } from "./Model";
import { RawModel530Data } from "../../cache/def/RawModel530";

export class Model530 {
    /**
     * Build a 377 Model from the rt4 idx7 byte decode. Mirrors the field
     * mapping in this comment table:
     *
     *   RawModel530.vertexCount           → Model.vertexCount
     *   RawModel530.vertexX/Y/Z           → Model.verticesX/Y/Z
     *   RawModel530.triangleCount         → Model.triangleCount
     *   RawModel530.triangleVertexA/B/C   → Model.trianglePointsX/Y/Z
     *   RawModel530.triangleColors        → Model.triangleColorValues
     *   RawModel530.triangleAlpha         → Model.triangleAlphaValues
     *   RawModel530.trianglePriorities    → Model.trianglePriorities
     *   RawModel530.triangleTextureIndex  → Model.texturePoints
     *   RawModel530.texturedCount         → Model.texturedTriangleCount
     *   RawModel530.textureFacesP/M/N     → Model.texturedTrianglePointsX/Y/Z
     *
     * After populating the fields the bounds (anInt1668-anInt1675, maxY)
     * are recomputed by walking the vertex list — Rasterizer3D depends
     * on those for clip-volume tests.
     */
    static fromRawModel530(d: RawModel530Data): Model {
        const m = new Model();
        m.vertexCount = d.vertexCount;
        m.verticesX = d.vertexX;
        m.verticesY = d.vertexY;
        m.verticesZ = d.vertexZ;

        m.triangleCount = d.triangleCount;
        m.trianglePointsX = d.triangleVertexA;
        m.trianglePointsY = d.triangleVertexB;
        m.trianglePointsZ = d.triangleVertexC;

        m.triangleColorValues = d.triangleColors;
        m.triangleAlphaValues = d.triangleAlpha;
        m.trianglePriorities = d.trianglePriorities;
        m.texturePoints = d.triangleTextureIndex;

        m.texturedTriangleCount = d.texturedCount;
        m.texturedTrianglePointsX = d.textureFacesP;
        m.texturedTrianglePointsY = d.textureFacesM;
        m.texturedTrianglePointsZ = d.textureFacesN;

        Model530.recomputeBounds(m);
        m.applyLighting(64, 850, -30, -50, -30, true);
        Model530.recomputeBounds(m);
        return m;
    }

    /**
     * Walk vertex positions to compute the same bound fields that the 377
     * renderer derives in Model.method583(). renderAtPoint() culls against
     * modelHeight / shadowIntensity before triangle projection, so leaving
     * those as constructor defaults makes valid 530 meshes disappear.
     *
     * Field names are the original anInt167x slots; renaming risks breaking
     * other unfocused renderer code so we keep them as-is.
     */
    private static recomputeBounds(m: Model): void {
        let minX = 32767, maxX = -32767, minY = 32767, maxY = -32767, minZ = 32767, maxZ = -32767;
        let radiusSq = 0;
        for (let i = 0; i < m.vertexCount; i++) {
            const x = m.verticesX[i];
            const y = m.verticesY[i];
            const z = m.verticesZ[i];
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            if (z < minZ) minZ = z;
            if (z > maxZ) maxZ = z;
            const r = x * x + z * z;
            if (r > radiusSq) radiusSq = r;
        }
        if (m.vertexCount === 0) {
            minX = maxX = minY = maxY = minZ = maxZ = 0;
        }
        m.modelHeight = -minY;
        m.maxY = maxY;
        m.shadowIntensity = Math.sqrt(radiusSq) | 0;
        m.anInt1674 = Math.sqrt(m.shadowIntensity * m.shadowIntensity + m.modelHeight * m.modelHeight) | 0;
        m.anInt1673 = m.anInt1674 + (Math.sqrt(m.shadowIntensity * m.shadowIntensity + m.maxY * m.maxY) | 0);
        m.anInt1669 = (minX << 16) + (maxX & 65535);
        m.anInt1670 = (maxZ << 16) + (minZ & 65535);
        m.anInt1668 = m.modelHeight;
        m.anInt1675 = m.modelHeight;
    }
}
