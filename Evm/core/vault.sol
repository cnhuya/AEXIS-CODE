// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PermissionedQiaraVault is ERC4626, Ownable {
    // Tracks how many assets a user is "permitted" to withdraw
    mapping(address => uint256) public withdrawalPermission;

    event PermissionGranted(address indexed user, uint256 amount);

    constructor(IERC20 _asset) 
        ERC4626(_asset) 
        ERC20("Qiara USDC Vault", "vQUSDC") 
        Ownable(msg.sender)
    {}

    /**
     * @dev Grant permission to a user to withdraw a specific amount of assets.
     * In your case, the "Validator/Relayer" would call this after validating the cross-chain proof.
     */
    function grantWithdrawalPermission(address user, uint256 amount) external onlyOwner {
        withdrawalPermission[user] += amount;
        emit PermissionGranted(user, amount);
    }

    /**
     * @dev Override maxWithdraw to limit it by the granted permission.
     */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 availableInShares = super.maxWithdraw(owner);
        uint256 permittedAmount = withdrawalPermission[owner];
        
        // Return the smaller of the two: what they own vs what they are allowed to take
        return permittedAmount < availableInShares ? permittedAmount : availableInShares;
    }

    /**
     * @dev Override maxRedeem to be consistent with maxWithdraw.
     */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        uint256 sharesForPermittedAssets = _convertToShares(withdrawalPermission[owner], Math.Rounding.Floor);
        uint256 actualShares = super.maxRedeem(owner);
        
        return sharesForPermittedAssets < actualShares ? sharesForPermittedAssets : actualShares;
    }

    /**
     * @dev Hook into the internal withdraw logic to consume the permission.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        require(assets <= withdrawalPermission[owner], "Vault: Withdrawal exceeds permissioned amount");
        
        // Decrease the permissioned amount (burn the "permission")
        withdrawalPermission[owner] -= assets;
        
        // Proceed with standard OZ ERC4626 withdrawal logic
        super._withdraw(caller, receiver, owner, assets, shares);
    }
}