// SceneKit's simd forms (Sources/SceneKit/SIMD.swift, SIMDNode.swift): the vector, matrix and
// quaternion functions a file that imports SceneKit names, and the nodes' simd properties
// reading and writing the same state as SceneKit's own. On Apple's platforms the functions are
// the simd module's, so the same checks hold Apple's answers.
import Testing
@testable import SceneKit

@Suite @MainActor struct SceneKitSIMDTests {
    private func close(_ a: Float, _ b: Float, _ tolerance: Float = 1e-4) -> Bool { abs(a - b) < tolerance }
    private func close(_ a: simd_float3, _ b: simd_float3, _ tolerance: Float = 1e-4) -> Bool {
        close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance) && close(a.z, b.z, tolerance)
    }

    @Test func vectorFunctions() {
        let a = simd_float3(3, 0, 4)
        #expect(close(simd_length(a), 5))
        #expect(close(simd_normalize(a), simd_float3(0.6, 0, 0.8)))
        #expect(close(simd_dot(a, simd_float3(1, 2, 3)), 15))
        #expect(simd_cross(simd_float3(1, 0, 0), simd_float3(0, 1, 0)) == simd_float3(0, 0, 1))
        #expect(close(simd_distance(simd_float3(1, 1, 1), simd_float3(1, 1, 3)), 2))
    }

    /// The AI globe's orientation: a rotation matrix from three axes becomes a quaternion
    /// that turns the axes the same way (here a right-handed set, so a rotation).
    @Test func quaternionsFromMatricesTurnLikeThem() {
        let outward = simd_normalize(simd_float3(1, 1, 0))
        let up = simd_float3(0, 0, 1)
        let right = simd_normalize(simd_cross(up, outward))
        let adjustedUp = simd_normalize(simd_cross(outward, right))
        let m = float3x3(columns: (right, adjustedUp, outward))
        let q = simd_quatf(m)
        #expect(close(q.length, 1))
        #expect(close(q.act(simd_float3(1, 0, 0)), right))
        #expect(close(q.act(simd_float3(0, 1, 0)), adjustedUp))
        #expect(close(q.act(simd_float3(0, 0, 1)), outward))
        #expect(close(m * simd_float3(0, 0, 1), outward))
    }

    @Test func quaternionArithmetic() {
        let quarter = simd_quatf(angle: .pi / 2, axis: simd_float3(0, 0, 1))
        #expect(close(quarter.act(simd_float3(1, 0, 0)), simd_float3(0, 1, 0)))
        #expect(close(quarter.angle, .pi / 2))
        #expect(close((quarter * quarter).act(simd_float3(1, 0, 0)), simd_float3(-1, 0, 0)))
        #expect(close((quarter * quarter.inverse).act(simd_float3(1, 2, 3)), simd_float3(1, 2, 3)))
        let half = simd_slerp(simd_quatf(angle: 0, axis: simd_float3(0, 0, 1)), quarter, 0.5)
        #expect(close(half.angle, .pi / 4))
        let turn = simd_quatf(from: simd_float3(1, 0, 0), to: simd_float3(0, 0, -1))
        #expect(close(turn.act(simd_float3(1, 0, 0)), simd_float3(0, 0, -1)))
    }

    @Test func matrixArithmetic() {
        var m = matrix_identity_float4x4
        m.columns.3 = simd_float4(1, 2, 3, 1)
        #expect(m * simd_float4(1, 1, 1, 1) == simd_float4(2, 3, 4, 1))
        let inverse = simd_inverse(m)
        #expect(inverse * simd_float4(2, 3, 4, 1) == simd_float4(1, 1, 1, 1))
        #expect(m * inverse == matrix_identity_float4x4)
        let r = simd_float4x4(simd_quatf(angle: .pi / 2, axis: simd_float3(0, 1, 0)))
        let turned = r * simd_float4(0, 0, 1, 0)
        #expect(close(simd_float3(turned.x, turned.y, turned.z), simd_float3(1, 0, 0)))
        #expect(close(simd_determinant(r), 1))
    }

    @Test func nodesReadAndWriteThroughTheSimdForms() {
        let node = SCNNode()
        node.simdPosition = simd_float3(1, 2, 3)
        #expect(node.position == SCNVector3(1, 2, 3))
        node.simdPosition = .zero
        node.simdPivot = matrix_identity_float4x4
        #expect(node.pivot == SCNMatrix4Identity)
        node.simdOrientation = simd_quatf(angle: .pi / 2, axis: simd_float3(0, 1, 0))
        #expect(close(node.rotation.w, .pi / 2) && close(node.rotation.y, 1))
        // The transform's translation is the last column; SceneKit keeps it in m41...m43.
        node.simdPosition = simd_float3(4, 5, 6)
        let t = node.simdTransform
        #expect(close(simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z), simd_float3(4, 5, 6)))
        #expect(SCNMatrix4(t) == node.transform)
        let parent = SCNNode()
        parent.simdPosition = simd_float3(10, 0, 0)
        parent.addChildNode(node)
        #expect(close(node.simdWorldPosition, simd_float3(14, 5, 6)))
        node.simdWorldPosition = simd_float3(0, 0, 0)
        #expect(close(node.simdPosition, simd_float3(-10, 0, 0)))
        #expect(close(node.simdWorldFront, simd_float3(-1, 0, 0)))
    }
}
