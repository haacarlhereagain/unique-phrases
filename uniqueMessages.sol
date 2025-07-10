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
        MessageStatus status;
        uint confirmationDelaySeconds;
        bool exists;
        string messageEncrypted;
        bytes32 key;
    }

    struct KeyInfo {
        bool exists;
        bytes32 messageId;
    }

    mapping(bytes32 => MessageInfo) private messages;
    mapping(bytes32 => uint256) private confirmationStartedAt;
    mapping(bytes32 => KeyInfo) private keys; 

    address public admin;

    event MessageAdded(bytes32 indexed messageId, address owner, MessageStatus status, string messageEncrypted);
    event OwnershipConfirmed(bytes32 indexed messageId, address confirmedOwner);
    event OwnershipTransferred(bytes32 indexed messageId, address oldOwner, address newOwner);
    event AdminChanged(address oldAdmin, address newAdmin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call");
        _;
    }

    modifier onlyOwner(bytes32 messageId) {
        require(messages[messageId].owner == msg.sender, "Only owner can call");
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

    function revokeMessage(bytes32 messageId, bytes32 key) external onlyAdmin {
        require(!keyExists(key), "Key has already used");
        MessageInfo storage messageInfo = messages[messageId];

        require(messageInfo.status == MessageStatus.ConfirmationAwaiting, "Invalid status");

        messageInfo.status = MessageStatus.Created;
        messageInfo.confirmationDelaySeconds = 0;

        attachKeyToMessage(key, messageId);
    }

    function addMessage(
        bytes32 messageId,
        bytes32 key,
        string calldata messageEncrypted
    ) external onlyAdmin {
        require(!keyExists(key), "Key has already used");
        require(bytes(messageEncrypted).length > 0, "Message cannot be empty");
        require(!messageExists(messageId), "Message already exists");

        messages[messageId] = MessageInfo({
            owner: admin,
            status: MessageStatus.Created,
            confirmationDelaySeconds: 0,
            exists: true,
            messageEncrypted: messageEncrypted,
            key: key
        });

        attachKeyToMessage(key, messageId);

        emit MessageAdded(messageId, admin, MessageStatus.Created, messageEncrypted);
    }

    function confirm(bytes32 key, address newOwner) external onlyAdmin {
        require(keyExists(key), "Key does not exist");

        KeyInfo storage keyInfo = keys[key];

        require(messageExists(keyInfo.messageId), "Message does not exist");

        MessageInfo storage messageInfo = messages[keyInfo.messageId];

        require(messageInfo.key == key, "Invalid key");

        require(messageInfo.status == MessageStatus.ConfirmationAwaiting, "Not in awaiting confirmation stage");

        uint256 startedAt = confirmationStartedAt[keyInfo.messageId];
        require(startedAt > 0, "Confirmation not started");

        uint256 delayEnd = startedAt + messageInfo.confirmationDelaySeconds;

        require(block.timestamp >= delayEnd, "Confirmation delay not passed");

        messageInfo.status = MessageStatus.Confirmed;
        messageInfo.confirmationDelaySeconds = 0;
        messageInfo.owner = newOwner;
        delete confirmationStartedAt[keyInfo.messageId];

        emit OwnershipConfirmed(keyInfo.messageId, newOwner);
    }

    function changeStatusToAwaitingConfirmation(
        bytes32 key,
        uint confirmationDelaySeconds
    ) external onlyAdmin {
        require(keyExists(key), "Key does not exist");

        KeyInfo storage keyInfo = keys[key];

        require(messageExists(keyInfo.messageId), "Message does not exist");

        MessageInfo storage messageInfo = messages[keyInfo.messageId];

        require(messageInfo.key == key, "Invalid key");

        require(messageInfo.status == MessageStatus.Created, "Status must be Created");

        messageInfo.status = MessageStatus.ConfirmationAwaiting;
        messageInfo.confirmationDelaySeconds = confirmationDelaySeconds;
        confirmationStartedAt[keyInfo.messageId] = block.timestamp;
    }

    function transferOwnershipImmediately(bytes32 messageId, address newOwner) external onlyOwner(messageId) {
        MessageInfo storage messageInfo = messages[messageId];

        address oldOwner = messageInfo.owner;
        messageInfo.owner = newOwner;

        emit OwnershipTransferred(messageId, oldOwner, newOwner);
    }

    function getMessageInfo(bytes32 messageId) external view returns (
        address owner,
        MessageStatus status,
        uint confirmationDelaySeconds,
        uint confirmationStartedTimestamp,
        string memory messageEncrypted
    ) {
        MessageInfo memory messageInfo = messages[messageId];

        return (
            messageInfo.owner,
            messageInfo.status,
            messageInfo.confirmationDelaySeconds,
            confirmationStartedAt[messageId],
            messageInfo.messageEncrypted
        );
    }

    function messageExists(bytes32 messageId) public view returns (bool) {
        return messages[messageId].exists;
    }

    function keyExists(bytes32 key) public view returns (bool) {
        KeyInfo storage keyInfo = keys[key];

        return keyInfo.exists;
    }

    function attachKeyToMessage(bytes32 key, bytes32 messageId) private {
        require(messageExists(messageId), "Message does not exist");
        require(!keyExists(key), "Key has already used");

        MessageInfo storage messageInfo = messages[messageId];

        messageInfo.key = key;

        keys[key] = KeyInfo({
            exists: true,
            messageId: messageId
        });
    }
}
