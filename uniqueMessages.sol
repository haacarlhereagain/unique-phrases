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
        string messageHash;
    }

    mapping(bytes32 => MessageInfo) private messages;
    mapping(bytes32 => uint256) private confirmationStartedAt;

    address public admin;

    // --- Events ---
    event MessageAdded(bytes32 indexed hash_, address owner, MessageStatus status, string messageHash);
    event OwnershipConfirmed(bytes32 indexed hash_, address confirmedOwner);
    event OwnershipTransferred(bytes32 indexed hash_, address oldOwner, address newOwner);
    event MessageRevertedToAdmin(bytes32 indexed hash_);
    event AdminChanged(address oldAdmin, address newAdmin);

    // --- Modifiers ---
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

    function createMessage(
        bytes32 hash_,
        bytes32 claimHash,
        uint confirmationDelaySeconds,
        uint confirmationPeriodSeconds,
        string memory messageHash
    ) external onlyAdmin {
        require(bytes(messageHash).length > 0, "Message cannot be empty");
        require(!messageExists(hash_), "Message already exists");

        messages[hash_] = MessageInfo({
            owner: admin,
            status: MessageStatus.Created,
            confirmationDelaySeconds: confirmationDelaySeconds,
            confirmationPeriodSeconds: confirmationPeriodSeconds,
            claimHash: claimHash,
            exists: true,
            messageHash: messageHash
        });

        emit MessageAdded(hash_, admin, MessageStatus.Created, messageHash);
    }

    function confirm(bytes32 hash_, address newOwner) external onlyAdmin {
        require(messageExists(hash_), "Message does not exist");

        MessageInfo storage info = messages[hash_];

        require(info.status == MessageStatus.ConfirmationAwaiting, "Not in awaiting confirmation stage");

        uint256 startedAt = confirmationStartedAt[hash_];
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
        delete confirmationStartedAt[hash_];

        emit OwnershipConfirmed(hash_, newOwner);
    }

    function revertToAdminIfExpiredBatch(bytes32[] calldata hashes) external onlyAdmin {
        for (uint i = 0; i < hashes.length; i++) {
            bytes32 hash_ = hashes[i];
            MessageInfo storage info = messages[hash_];

            if (info.status == MessageStatus.ConfirmationAwaiting && confirmationStartedAt[hash_] > 0) {
                uint256 startedAt = confirmationStartedAt[hash_];
                uint256 expirationTime = startedAt + info.confirmationDelaySeconds + info.confirmationPeriodSeconds;

                if (block.timestamp > expirationTime) {
                    address oldOwner = info.owner;

                    info.owner = admin;
                    info.status = MessageStatus.Created;
                    info.confirmationDelaySeconds = 0;
                    info.confirmationPeriodSeconds = 0;
                    delete confirmationStartedAt[hash_];

                    emit MessageRevertedToAdmin(hash_);
                    emit OwnershipTransferred(hash_, oldOwner, admin);
                }
            }
        }
    }

    function changeStatusToAwaitingConfirmation(bytes32 hash_) external onlyAdmin {
        require(messageExists(hash_), "Message does not exist");

        MessageInfo storage info = messages[hash_];
        require(info.status == MessageStatus.Created, "Status must be Created");

        info.status = MessageStatus.ConfirmationAwaiting;
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
        uint confirmationPeriodSeconds,
        uint confirmationStartedTimestamp,
        bytes32 claimHash,
        string memory messageHash
    ) {
        MessageInfo memory info = messages[hash_];
        return (
            info.owner,
            info.status,
            info.confirmationDelaySeconds,
            info.confirmationPeriodSeconds,
            confirmationStartedAt[hash_],
            info.claimHash,
            info.messageHash
        );
    }

    function messageExists(bytes32 hash_) public view returns (bool) {
        return messages[hash_].exists == true;
    }
}
