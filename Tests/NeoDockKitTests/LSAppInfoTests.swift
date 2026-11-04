import Testing
@testable import NeoDockKit

@Suite struct LSAppInfoTests {
    @Test func findLiefertAlleKennungenInLsappinfoSchreibweise() {
        let output = """
        ASN:0x0-0x2edbed9-"req2":
        ASN:0x0-0x1d7ed7d-"Numbers":

        """
        #expect(LSAppInfo.asns(inFindOutput: output) == ["ASN:0x0-0x2edbed9:", "ASN:0x0-0x1d7ed7d:"])
    }

    @Test func findOhneTrefferIstLeer() {
        #expect(LSAppInfo.asns(inFindOutput: "").isEmpty)
    }

    @Test func kennungImAppNamenZaehltNicht() {
        let output = #"ASN:0x0-0x10-"Name ASN:0x0-0x99-":"#
        #expect(LSAppInfo.asns(inFindOutput: output) == ["ASN:0x0-0x10:"])
    }

    @Test func infoLiefertDiePid() {
        let output = """
        [ NULL ]  [ NULL ]
            bundleID=[ NULL ]
            bundle path=[ NULL ]
            executable path=[ NULL ]
            pid = 1781 !cgsConnection !signalled type=[ NULL ]  flavor=[ NULL ]  Version=[ NULL ]  Arch=!!none

        """
        #expect(LSAppInfo.pid(inInfoOutput: output) == 1781)
    }

    @Test func infoZuBeendeterAppIstNil() {
        #expect(LSAppInfo.pid(inInfoOutput: "") == nil)
    }
}
