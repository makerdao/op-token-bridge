// L1GovernanceRelay.spec

using MessengerMock as l1messenger;

methods {
    // storage variables
    function wards(address) external returns (uint256) envfree;
    // immutables
    function l2GovernanceRelay() external returns (address) envfree;
    function messenger() external returns (address) envfree;
    //
    function l1messenger.getGovMessageHash(address,bytes) external returns (bytes32) envfree;
    function l1messenger.lastTarget() external returns (address) envfree;
    function l1messenger.lastMessageHash() external returns (bytes32) envfree;
    function l1messenger.lastMinGasLimit() external returns (uint32) envfree;
    //
    function _.sendMessage(address,bytes,uint32) external => DISPATCHER(true);
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "Assert 1";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 1, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 0, "Assert 1";
    assert wardsOtherAfter == wardsOtherBefore, "Assert 2";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting relay
rule relay(address target, bytes targetData, uint32 minGasLimit) {
    env e;

    address l2GovernanceRelay = l2GovernanceRelay();

    bytes32 message = l1messenger.getGovMessageHash(target, targetData);

    relay(e, target, targetData, minGasLimit);

    address lastTargetAfter = l1messenger.lastTarget();
    bytes32 lastMessageHashAfter = l1messenger.lastMessageHash();
    uint32  lastMinGasLimitAfter = l1messenger.lastMinGasLimit();

    assert lastTargetAfter == l2GovernanceRelay, "Assert 1";
    assert lastMessageHashAfter == message, "Assert 2";
    assert lastMinGasLimitAfter == minGasLimit, "Assert 3";
}

// Verify revert rules on relay
rule relay_revert(address target, bytes targetData, uint32 minGasLimit) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    relay@withrevert(e, target, targetData, minGasLimit);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}
