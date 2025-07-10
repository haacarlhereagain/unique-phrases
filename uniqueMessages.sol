// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MessagesOwnershipHashed {
    enum MessageStatus {
        Created,
        ConfirmationAwaiting,
        Confirmed
    }

    struct MessageInfo {
        address owner;
        bytes32 claimHash;
        MessageStatus status;
        uint confirmationDelaySeconds;
        bool exists;
        string messageHash;
        bool generated;
    }

    mapping(bytes32 => MessageInfo) private messages;
    mapping(bytes32 => uint256) private confirmationStartedAt;
    mapping(bytes32 => bool) private claimHashes; 

    address public admin;

    event MessageAdded(bytes32 indexed hash_, address owner, MessageStatus status, string messageHash);
    event OwnershipConfirmed(bytes32 indexed hash_, address confirmedOwner);
    event OwnershipTransferred(bytes32 indexed hash_, address oldOwner, address newOwner);
    event AdminChanged(address oldAdmin, address newAdmin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call");
        _;
    }

    modifier onlyOwner(bytes32 hash_) {
        require(messages[hash_].owner == msg.sender, "Only owner can call");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "New admin cannot be zero address");
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }

    function revokeMessage(bytes32 hash_, bytes32 claimHash) external onlyAdmin {
        require(!claimHashExists(claimHash), "Claim has already used");
        MessageInfo storage info = messages[hash_];

        require(info.status == MessageStatus.ConfirmationAwaiting, "Invalid status");

        info.status = MessageStatus.Created;
        info.claimHash = claimHash;
        info.confirmationDelaySeconds = 0;

        markClaimHashAsUsed(claimHash);
    }

    function addMessage(
        bytes32 hash_,
        bytes32 claimHash,
        string calldata messageHash,
        bool generated
    ) external onlyAdmin {
        require(!claimHashExists(claimHash), "Claim has already used");
        require(bytes(messageHash).length > 0, "Message cannot be empty");
        require(!messageExists(hash_), "Message already exists");

        messages[hash_] = MessageInfo({
            owner: admin,
            status: MessageStatus.Created,
            confirmationDelaySeconds: 0,
            claimHash: claimHash,
            exists: true,
            messageHash: messageHash,
            generated: generated
        });

        markClaimHashAsUsed(claimHash);

        emit MessageAdded(hash_, admin, MessageStatus.Created, messageHash);
    }

    function confirm(bytes32 hash_, address newOwner) external onlyAdmin {
        require(messageExists(hash_), "Message does not exist");

        MessageInfo storage info = messages[hash_];

        require(info.status == MessageStatus.ConfirmationAwaiting, "Not in awaiting confirmation stage");

        uint256 startedAt = confirmationStartedAt[hash_];
        require(startedAt > 0, "Confirmation not started");

        uint256 delayEnd = startedAt + info.confirmationDelaySeconds;

        require(block.timestamp >= delayEnd, "Confirmation delay not passed");

        info.status = MessageStatus.Confirmed;
        info.confirmationDelaySeconds = 0;
        info.owner = newOwner;
        info.claimHash = 0;
        delete confirmationStartedAt[hash_];

        emit OwnershipConfirmed(hash_, newOwner);
    }

    function changeStatusToAwaitingConfirmation(
        bytes32 hash_,
        uint confirmationDelaySeconds
    ) external onlyAdmin {
        require(messageExists(hash_), "Message does not exist");

        MessageInfo storage info = messages[hash_];
        require(info.status == MessageStatus.Created, "Status must be Created");

        info.status = MessageStatus.ConfirmationAwaiting;
        info.confirmationDelaySeconds = confirmationDelaySeconds;
        confirmationStartedAt[hash_] = block.timestamp;
    }

    function transferOwnershipImmediately(bytes32 hash_, address newOwner) external onlyOwner(hash_) {
        MessageInfo storage info = messages[hash_];

        address oldOwner = info.owner;
        info.owner = newOwner;

        emit OwnershipTransferred(hash_, oldOwner, newOwner);
    }

    function getMessageInfo(bytes32 hash_) external view returns (
        address owner,
        MessageStatus status,
        uint confirmationDelaySeconds,
        uint confirmationStartedTimestamp,
        bytes32 claimHash,
        string memory messageHash
    ) {
        MessageInfo memory info = messages[hash_];

        return (
            info.owner,
            info.status,
            info.confirmationDelaySeconds,
            confirmationStartedAt[hash_],
            info.claimHash,
            info.messageHash
        );
    }

    function messageExists(bytes32 hash_) public view returns (bool) {
        return messages[hash_].exists;
    }

    function claimHashExists(bytes32 claimHash) public view returns (bool) {
        return claimHashes[claimHash];
    }

    function markClaimHashAsUsed(bytes32 claimHash) private {
        claimHashes[claimHash] = true;
    }

    function isGenerated(bytes32 hash_) external view returns (bool) {
        require(messageExists(hash_), "Message does not exist");
        return messages[hash_].generated;
    }
}
