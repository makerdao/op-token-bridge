// L2GovernanceRelay.spec

using MessengerMock as l2messenger;

methods {
    // immutables
    function l1GovernanceRelay() external returns (address) envfree;
    function messenger() external returns (address) envfree;
    //
    function l2messenger.xDomainMessageSender() external returns (address) envfree;
}

definition addrZero() returns address = 0x0000000000000000000000000000000000000000;

persistent ghost bool called;
persistent ghost address calledAddr;
persistent ghost mathint dataLength;
persistent ghost bool success;
hook DELEGATECALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    called = true;
    calledAddr = addr;
    dataLength = argsLength;
    success = rc != 0;
}

// Verify correct storage changes for non reverting relay
rule relay(address target, bytes targetData) {
    env e;

    relay(e, target, targetData);

    assert called, "Assert 1";
    assert calledAddr == target, "Assert 2";
    assert dataLength == targetData.length, "Assert 3";
    assert success, "Assert 4";
}

// Verify revert rules on relay
rule relay_revert(address target, bytes targetData) {
    env e;

    address l1GovernanceRelay = l1GovernanceRelay();
    address messenger = messenger();
    address xDomainMessageSender = l2messenger.xDomainMessageSender();

    relay@withrevert(e, target, targetData);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.msg.sender != messenger || xDomainMessageSender != l1GovernanceRelay;
    bool revert3 = !success;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}
