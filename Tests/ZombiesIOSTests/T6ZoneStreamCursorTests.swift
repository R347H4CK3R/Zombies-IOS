import XCTest
@testable import ZombiesIOS

final class T6ZoneStreamCursorTests: XCTestCase {
    func testDecodesT6PointerKindsAndThreeBitBlockOffsets() throws {
        XCTAssertEqual(T6ZonePointer.decode(0), .null)
        XCTAssertEqual(T6ZonePointer.decode(0xFFFF_FFFF), .following)
        XCTAssertEqual(T6ZonePointer.decode(0xFFFF_FFFE), .insert)

        // Zone offsets are stored +1; T6 reserves the top three bits for block id.
        let encoded = UInt32((5 << 29) | 0x0012_3456) &+ 1
        XCTAssertEqual(T6ZonePointer.decode(encoded), .offset(block: 5, offset: 0x0012_3456))
    }

    func testNormalBlockFollowingPayloadConsumesSerializedBytes() throws {
        let data = Data(0..<32)
        var cursor = try T6ZoneStreamCursor(
            serializedData: data,
            blockSizes: [64, 64, 64, 64, 64, 64, 64, 64],
            serializedOffset: 0
        )
        try cursor.pushBlock(5)
        let slice = try cursor.resolveFollowing(alignment: 4, length: 4)
        XCTAssertEqual(Array(slice), [0, 1, 2, 3])
        XCTAssertEqual(cursor.currentSerializedOffset, 4)
        XCTAssertEqual(cursor.blockOffset(5), 4)
    }

    func testRuntimeBlockConsumesLogicalSpaceButNoSerializedBytes() throws {
        let data = Data(0..<32)
        var cursor = try T6ZoneStreamCursor(
            serializedData: data,
            blockSizes: [64, 64, 64, 64, 64, 64, 64, 64],
            serializedOffset: 0
        )
        try cursor.pushBlock(1)
        let slice = try cursor.resolveFollowing(alignment: 4, length: 12)
        XCTAssertTrue(slice.isEmpty)
        XCTAssertEqual(cursor.currentSerializedOffset, 0)
        XCTAssertEqual(cursor.blockOffset(1), 12)
    }

    func testTempBlockPopRestoresLogicalOffsetButKeepsSerializedProgress() throws {
        let data = Data(0..<64)
        var cursor = try T6ZoneStreamCursor(
            serializedData: data,
            blockSizes: [64, 64, 64, 64, 64, 64, 64, 64],
            serializedOffset: 0
        )
        try cursor.pushBlock(0)
        _ = try cursor.resolveFollowing(alignment: 4, length: 8)
        XCTAssertEqual(cursor.blockOffset(0), 8)
        XCTAssertEqual(cursor.currentSerializedOffset, 8)
        try cursor.popBlock()
        XCTAssertEqual(cursor.blockOffset(0), 0)
        XCTAssertEqual(cursor.currentSerializedOffset, 8)
    }

    func testAlignmentAdvancesLogicalBlockWithoutInventingSerializedPadding() throws {
        let data = Data(0..<64)
        var cursor = try T6ZoneStreamCursor(
            serializedData: data,
            blockSizes: [64, 64, 64, 64, 64, 64, 64, 64],
            serializedOffset: 0
        )
        try cursor.pushBlock(5)
        _ = try cursor.resolveFollowing(alignment: 1, length: 3)
        let second = try cursor.resolveFollowing(alignment: 8, length: 2)
        XCTAssertEqual(Array(second), [3, 4])
        XCTAssertEqual(cursor.blockOffset(5), 10)
        XCTAssertEqual(cursor.currentSerializedOffset, 5)
    }

    func testTruncatedFollowingPayloadThrows() throws {
        var cursor = try T6ZoneStreamCursor(
            serializedData: Data([1, 2, 3]),
            blockSizes: [64, 64, 64, 64, 64, 64, 64, 64],
            serializedOffset: 0
        )
        try cursor.pushBlock(5)
        XCTAssertThrowsError(try cursor.resolveFollowing(alignment: 1, length: 4))
    }
}
