/**
 * Helper Script returning `points.json` vector file's test cases as Ethereum
 * ABI encoded uint[].
 *
 * Usage:
 * ```bash
 * $ node test/vectors/points.js
 * ```
 *
 * Outputs:
 * Prints an ABI encoded uint[]. The elements should be read sequentially.
 * The first element is the x coordinate of the first point. The second element
 * the y coordinate of the first point. Afterwards the x coordinate of the
 * second point, and so forth.
 *
 * One test case contains 3 points - p, q, and expected - for which the
 * following should hold: p + q = expected
 */
const { readFileSync } = require('fs');
const { secp256k1 } = require('@noble/curves/secp256k1');
const { encodeAbiParameters } = require("viem");

const Point = secp256k1.ProjectivePoint;

function main() {
    const points = JSON.parse(readFileSync("test/vectors/points.json"));

    let out = [];
    for (const vector of points.vectors) {
        const { P, Q, expected } = vector;

        let p = Point.fromHex(P);
        let q = Point.fromHex(Q);
        let e = expected ? Point.fromHex(expected) : q;

        // Convert to Affine form.
        p = p.toAffine();
        q = q.toAffine();
        e = e.toAffine();

        out.push(
            p.x,
            p.y,
            q.x,
            q.y,
            e.x,
            e.y,
        );
    }

    // Encode test cases to uint[].
    const encoded = encodeAbiParameters(
        [{ type: 'uint[]' }],
        [out]
    )
    console.log(encoded);
}

main();
