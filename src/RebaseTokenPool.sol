// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {TokenPool} from "ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from "ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    uint8 private constant LOCAL_TOKEN_DECIMALS = 18;

    constructor(IERC20 token, address[] memory allowlist, address rmnProxy, address router)
        TokenPool(token, LOCAL_TOKEN_DECIMALS, allowlist, rmnProxy, router)
    {}

    /**
     * @notice This locks/burns the token from the crosschain pool when a user sends funds.
     * @param lockOrBurnIn The data for the lock/burn operation.
     * @return lockOrBurnOut The data for the lock/burn operation.
     */
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);

        address originalSender = lockOrBurnIn.originalSender;
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(originalSender);

        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);

        address receiver = releaseOrMintIn.receiver;
        uint256 amount = releaseOrMintIn.amount;
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        IRebaseToken(address(i_token)).mint(receiver, amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: amount});
    }
}
