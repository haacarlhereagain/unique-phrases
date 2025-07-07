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
        uint confirmationPeriodSeconds;
        bool exists;
        string message;
    }

    mapping(bytes32 => MessageInfo) private messages;
    mapping(bytes32 => uint256) private confirmationStartedAt;

    address public admin;

    // --- Events ---
    event MessageAdded(bytes32 indexed messageHash, address owner, MessageStatus status, string message);
    event OwnershipConfirmed(bytes32 indexed messageHash, address confirmedOwner);
    event OwnershipTransferred(bytes32 indexed messageHash, address oldOwner, address newOwner);
    event MessageRevertedToAdmin(bytes32 indexed messageHash);
    event MessageDeleted(bytes32 indexed messageHash, address by);
    event AdminChanged(address oldAdmin, address newAdmin);

    // --- Modifiers ---
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call");
        _;
    }

    modifier onlyOwner(bytes32 messageHash) {
        require(messages[messageHash].owner == msg.sender, "Only owner can call");
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

    function createMessage(
        bytes32 messageHash,
        bytes32 claimHash,
        uint confirmationDelaySeconds,
        uint confirmationPeriodSeconds,
        string memory message
    ) external onlyAdmin {
        require(bytes(message).length > 0, "Message cannot be empty");
        require(messageHash != bytes32(0), "Invalid message hash");
        require(!messageExists(messageHash), "Message already exists");

        messages[messageHash] = MessageInfo({
            owner: admin,
            status: MessageStatus.Created,
            confirmationDelaySeconds: confirmationDelaySeconds,
            confirmationPeriodSeconds: confirmationPeriodSeconds,
            claimHash: claimHash,
            exists: true,
            message: message
        });

        emit MessageAdded(messageHash, admin, MessageStatus.Created, message);
    }

    function confirm(bytes32 messageHash, address newOwner) external onlyAdmin {
        require(messageExists(messageHash), "Message does not exist");

        MessageInfo storage info = messages[messageHash];

        require(info.status == MessageStatus.ConfirmationAwaiting, "Not in awaiting confirmation stage");

        uint256 startedAt = confirmationStartedAt[messageHash];
        require(startedAt > 0, "Confirmation not started");

        uint256 delayEnd = startedAt + info.confirmationDelaySeconds;
        uint256 periodEnd = delayEnd + info.confirmationPeriodSeconds;

        require(block.timestamp >= delayEnd, "Confirmation delay not passed");
        require(block.timestamp <= periodEnd, "Confirmation period expired");

        info.status = MessageStatus.Confirmed;
        info.confirmationDelaySeconds = 0;
        info.confirmationPeriodSeconds = 0;
        info.owner = newOwner;
        info.claimHash = 0;
        delete confirmationStartedAt[messageHash];

        emit OwnershipConfirmed(messageHash, newOwner);
    }

    function revertToAdminIfExpiredBatch(bytes32[] calldata messageHashes) external onlyAdmin {
        for (uint i = 0; i < messageHashes.length; i++) {
            bytes32 messageHash = messageHashes[i];
            MessageInfo storage info = messages[messageHash];

            if (info.status == MessageStatus.ConfirmationAwaiting && confirmationStartedAt[messageHash] > 0) {
                uint256 startedAt = confirmationStartedAt[messageHash];
                uint256 expirationTime = startedAt + info.confirmationDelaySeconds + info.confirmationPeriodSeconds;

                if (block.timestamp > expirationTime) {
                    address oldOwner = info.owner;

                    info.owner = admin;
                    info.status = MessageStatus.Created;
                    info.confirmationDelaySeconds = 0;
                    info.confirmationPeriodSeconds = 0;
                    delete confirmationStartedAt[messageHash];

                    emit MessageRevertedToAdmin(messageHash);
                    emit OwnershipTransferred(messageHash, oldOwner, admin);
                }
            }
        }
    }

    function transferOwnershipImmediately(bytes32 messageHash, address newOwner) external onlyOwner(messageHash) {
        MessageInfo storage info = messages[messageHash];

        address oldOwner = info.owner;
        info.owner = newOwner;

        emit OwnershipTransferred(messageHash, oldOwner, newOwner);
    }

    function changeStatusToAwaitingConfirmation(bytes32 messageHash) external onlyAdmin {
        require(messageExists(messageHash), "Message does not exist");

        MessageInfo storage info = messages[messageHash];
        require(info.status == MessageStatus.Created, "Status must be Created");

        info.status = MessageStatus.ConfirmationAwaiting;
        confirmationStartedAt[messageHash] = block.timestamp;
    }

    function deleteMessage(bytes32 messageHash) external onlyAdmin {
        MessageInfo storage info = messages[messageHash];
        require(info.owner == admin, "Message owner is not admin");

        delete messages[messageHash];
        delete confirmationStartedAt[messageHash];

        emit MessageDeleted(messageHash, msg.sender);
    }

    function getMessageInfo(bytes32 messageHash) external view returns (
        address owner,
        MessageStatus status,
        uint confirmationDelaySeconds,
        uint confirmationPeriodSeconds,
        uint confirmationStartedTimestamp,
        bytes32 claimHash,
        string memory message
    ) {
        MessageInfo memory info = messages[messageHash];
        return (
            info.owner,
            info.status,
            info.confirmationDelaySeconds,
            info.confirmationPeriodSeconds,
            confirmationStartedAt[messageHash],
            info.claimHash,
            info.message
        );
    }

    function messageExists(bytes32 messageHash) public view returns (bool) {
        return messages[messageHash].exists == true;
    }
}
