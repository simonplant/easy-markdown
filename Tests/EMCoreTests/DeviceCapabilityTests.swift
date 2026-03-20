import Testing
@testable import EMCore

@Suite("DeviceCapability")
struct DeviceCapabilityTests {

    @Test("detect returns a valid capability")
    func detectReturnsValue() {
        let capability = DeviceCapability.detect()
        // On any test host, detect() should return one of the two cases.
        #expect(capability == .fullAI || capability == .noAI)
    }

    @Test("Enum cases are distinct")
    func casesAreDistinct() {
        #expect(DeviceCapability.fullAI != DeviceCapability.noAI)
    }

    @Test("fullAI and noAI are equatable")
    func equatable() {
        #expect(DeviceCapability.fullAI == .fullAI)
        #expect(DeviceCapability.noAI == .noAI)
        #expect(DeviceCapability.fullAI != .noAI)
    }
}
