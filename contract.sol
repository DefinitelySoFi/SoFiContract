// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DefinitelyKeysV1 is Ownable, ReentrancyGuard  {

    constructor() Ownable(msg.sender) {
        bytes32 initialInviteCode = keccak256(abi.encodePacked("DEFINITELY"));
        referralOwners[initialInviteCode] = msg.sender;
        protocolFeeDestination = msg.sender;
        protocolFeePercent = 50000000000000000;
        subjectFeePercent = 50000000000000000;
        referralFeePercent = 10000000000000000;
    }

    address public protocolFeeDestination;
    uint256 public protocolFeePercent;
    uint256 public subjectFeePercent;
    uint256 public referralFeePercent;

    event Trade(address trader, address subject, bool isBuy, uint256 keyAmount, uint256 ethAmount, uint256 balance, uint256 supply);
    event Transfer(address from, address to, uint256 amount, address subject);

    mapping(address => mapping(address => uint256)) public keysBalance;
    mapping(address => uint256) public keysSupply;
    mapping(bytes32 => address) public referralOwners;
    mapping(address => bytes32) public subjectReferralTargets;

    function setFeeDestination(address _feeDestination) public onlyOwner {
        protocolFeeDestination = _feeDestination;
    }

    function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
        protocolFeePercent = _feePercent;
    }

    function setSubjectFeePercent(uint256 _feePercent) public onlyOwner {
        subjectFeePercent = _feePercent;
    }

    function setReferralFeePercent(uint256 _feePercent) public onlyOwner {
        referralFeePercent = _feePercent;
    }

    function createSubject(bytes32 inviteCode, bytes32 myInviteCode) public payable nonReentrant {
        require(msg.value >= 0.001 ether, "DefinitelyKeysV1: createSubject: insufficient funds");
        require(keysSupply[msg.sender] == 0, "DefinitelyKeysV1: createSubject: keysSubject already exists");
        keysSupply[msg.sender] = 100;
        keysBalance[msg.sender][msg.sender] = 100;
        emit Trade(msg.sender, referralOwners[inviteCode], true, 100, 0, 100, 100);
        (bool success, ) = protocolFeeDestination.call{value: 0.001 ether}(""); //account opening fee
        require(referralOwners[myInviteCode] == address(0), "DefinitelyKeysV1: createSubject: invite code already set");
        referralOwners[myInviteCode] = msg.sender;
        require(referralOwners[inviteCode] != address(0), "DefinitelyKeysV1: createSubject: invalid invite code");
        subjectReferralTargets[msg.sender] = inviteCode;
        require(success, "DefinitelyKeysV1: createSubject: account creation failed");
    }

    function getTotalCostForRange(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = (supply - 1 )* (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000000000;
    }

    function buyKeys(address keysSubject, uint256 amount) public payable nonReentrant  {
        require(amount > 0, "DefinitelyKeysV1: buyKeys: 0 amount");
        uint256 supply = keysSupply[keysSubject];
        uint256 totalCost = getTotalCostForRange(supply, amount);
        keysSupply[keysSubject] = supply + amount;
        keysBalance[keysSubject][msg.sender] += amount;
        uint256 protocolFee = totalCost * protocolFeePercent / 1 ether;
        uint256 subjectFee = totalCost * subjectFeePercent / 1 ether;
        uint256 referralFee = totalCost * referralFeePercent / 1 ether;
        uint256 totalFees = totalCost + protocolFee + subjectFee + referralFee;
        require(msg.value >= totalFees, "DefinitelyKeysV1: buyKeys: insufficient funds");
        if(msg.value > totalFees) {
            uint256 refundAmount = msg.value - totalFees;
            (bool refundSuccess,) = msg.sender.call{value: refundAmount}("");
            require(refundSuccess, "DefinitelyKeysV1: buyKeys: Refund failed");
        }
        emit Trade(msg.sender, keysSubject, true, amount, totalCost, keysBalance[keysSubject][msg.sender], supply + amount);
        address referralOwner = referralOwners[subjectReferralTargets[keysSubject]];
        (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success2, ) = keysSubject.call{value: subjectFee}("");
        (bool success3, ) = referralOwner.call{value: referralFee}("");
        require(success1 && success2 && success3, "DefinitelyKeysV1: buyKeys: transfer failed");
    }

    function sellKeys(address keysSubject, uint256 amount, uint256 minEthReturn) public nonReentrant {
        require(amount > 0, "DefinitelyKeysV1: sellKeys: 0 amount");
        uint256 supply = keysSupply[keysSubject];
        require(supply - amount >= 100, "DefinitelyKeysV1: sellKeys: last 100 unit cannot be sold");
        require(keysBalance[keysSubject][msg.sender] >= amount, "DefinitelyKeysV1: sellKeys: insufficient keys");
        uint256 totalCost =  getTotalCostForRange(supply - amount, amount);
        keysSupply[keysSubject] = supply - amount;
        keysBalance[keysSubject][msg.sender] -= amount;
        uint256 protocolFee = totalCost * protocolFeePercent / 1 ether;
        uint256 subjectFee = totalCost * subjectFeePercent / 1 ether;
        uint256 referralFee = totalCost * referralFeePercent / 1 ether;
        require(totalCost - protocolFee - subjectFee - referralFee >= minEthReturn, "DefinitelyKeysV1: sellKeys: Slippage too high");
        emit Trade(msg.sender, keysSubject, false, amount, totalCost, keysBalance[keysSubject][msg.sender], supply - amount);
        address referralOwner = referralOwners[subjectReferralTargets[keysSubject]];
        (bool success1,) = msg.sender.call{value: totalCost - protocolFee - subjectFee - referralFee}("");
        (bool success2,) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success3,) = keysSubject.call{value: subjectFee}("");
        (bool success4,) = referralOwner.call{value: referralFee}("");
        require(success1 && success2 && success3 && success4, "DefinitelyKeysV1: sellKeys: transfer failed");
    }

    function transferKeys(address keysSubject, address to, uint256 amount) public nonReentrant {
        require(keysBalance[keysSubject][msg.sender] >= amount, "DefinitelyKeysV1: transferKeys: insufficient balance");
        require(to != address(0), "DefinitelyKeysV1: transferKeys: transfer to the zero address");
        keysBalance[keysSubject][msg.sender] -= amount;
        keysBalance[keysSubject][to] += amount;
        emit Transfer(msg.sender, to, amount, keysSubject);
    }
}
