// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import '../modules/uniswap/v2/V2SwapRouter.sol';
import '../modules/uniswap/v3/V3SwapRouter.sol';
import '../modules/Payments.sol';
import '../base/RouterCallbacks.sol';
import '../libraries/Commands.sol';
import {ERC721} from 'solmate/src/tokens/ERC721.sol';
import {ERC1155} from 'solmate/src/tokens/ERC1155.sol';
import {ICryptoPunksMarket} from '../interfaces/external/ICryptoPunksMarket.sol';

contract Dispatcher is V2SwapRouter, V3SwapRouter, RouterCallbacks {
    address immutable PERMIT_POST;

    error InvalidCommandType(uint256 commandType);
    error InvalidOwnerERC721();
    error InvalidOwnerERC1155();

    constructor(
        address permitPost,
        address v2Factory,
        address v3Factory,
        bytes32 pairInitCodeHash,
        bytes32 poolInitCodeHash
    ) V2SwapRouter(v2Factory, pairInitCodeHash) V3SwapRouter(v3Factory, poolInitCodeHash) {
        PERMIT_POST = permitPost;
    }

    /// @notice executes the given command with the given inputs
    /// @param command The command to execute
    /// @param inputs The inputs to execute the command with
    /// @return success true on success, false on failure
    /// @return output The outputs, if any from the command
    function dispatch(uint256 command, bytes memory inputs) internal returns (bool success, bytes memory output) {
        success = true;
        if (command == Commands.PERMIT) {
            // state[state.length] = abi.encode(msg.sender);
            // (success, output) = permitPost.call(state[0]);
            // bytes memory inputs = state.build(bytes4(0), indices);
            // (address some, address parameters, uint256 forPermit) = abi.decode(inputs, (address, address, uint));
            //
            // permitPost.permitWithNonce(msg.sender, some, parameters, forPermit);
        } else if (command == Commands.TRANSFER) {
            (address token, address recipient, uint256 value) = abi.decode(inputs, (address, address, uint256));
            Payments.pay(token, recipient, value);
        } else if (command == Commands.V2_SWAP_EXACT_IN) {
            (uint256 amountOutMin, address[] memory path, address recipient) =
                abi.decode(inputs, (uint256, address[], address));
            v2SwapExactInput(amountOutMin, path, recipient);
        } else if (command == Commands.V2_SWAP_EXACT_OUT) {
            (uint256 amountOut, uint256 amountInMax, address[] memory path, address recipient) =
                abi.decode(inputs, (uint256, uint256, address[], address));
            v2SwapExactOutput(amountOut, amountInMax, path, recipient);
        } else if (command == Commands.V3_SWAP_EXACT_IN) {
            (address recipient, uint256 amountOut, uint256 amountInMaximum, bytes memory path) =
                abi.decode(inputs, (address, uint256, uint256, bytes));
            v3SwapExactInput(recipient, amountOut, amountInMaximum, path);
        } else if (command == Commands.V3_SWAP_EXACT_OUT) {
            (address recipient, uint256 amountIn, uint256 amountOutMin, bytes memory path) =
                abi.decode(inputs, (address, uint256, uint256, bytes));
            v3SwapExactOutput(recipient, amountIn, amountOutMin, path);
        } else if (command == Commands.SEAPORT) {
            (uint256 value, bytes memory data) = abi.decode(inputs, (uint256, bytes));
            (success, output) = Constants.SEAPORT.call{value: value}(data);
        } else if (command == Commands.NFTX) {
            (uint256 value, bytes memory data) = abi.decode(inputs, (uint256, bytes));
            (success, output) = Constants.NFTX_ZAP.call{value: value}(data);
        } else if (command == Commands.LOOKS_RARE_721) {
            (success, output) = callAndTransfer721(inputs, Constants.LOOKS_RARE);
        } else if (command == Commands.X2Y2_721) {
            (success, output) = callAndTransfer721(inputs, Constants.X2Y2);
        } else if (command == Commands.LOOKS_RARE_1155) {
            (success, output) = callAndTransfer1155(inputs, Constants.LOOKS_RARE);
        } else if (command == Commands.X2Y2_1155) {
            (success, output) = callAndTransfer1155(inputs, Constants.X2Y2);
        } else if (command == Commands.FOUNDATION) {
            (success, output) = callAndTransfer721(inputs, Constants.FOUNDATION);
        } else if (command == Commands.SUDOSWAP) {
            (uint256 value, bytes memory data) = abi.decode(inputs, (uint256, bytes));
            (success, output) = Constants.SUDOSWAP.call{value: value}(data);
        } else if (command == Commands.NFT20) {
            (uint256 value, bytes memory data) = abi.decode(inputs, (uint256, bytes));
            (success, output) = Constants.NFT20_ZAP.call{value: value}(data);
        } else if (command == Commands.SWEEP) {
            (address token, address recipient, uint256 amountMin) = abi.decode(inputs, (address, address, uint256));
            Payments.sweep(token, recipient, amountMin);
        } else if (command == Commands.WRAP_ETH) {
            (address recipient, uint256 amountMin) = abi.decode(inputs, (address, uint256));
            Payments.wrapETH(recipient, amountMin);
        } else if (command == Commands.UNWRAP_WETH) {
            (address recipient, uint256 amountMin) = abi.decode(inputs, (address, uint256));
            Payments.unwrapWETH9(recipient, amountMin);
        } else if (command == Commands.PAY_PORTION) {
            (address token, address recipient, uint256 bips) = abi.decode(inputs, (address, address, uint256));
            Payments.payPortion(token, recipient, bips);
        } else if (command == Commands.OWNERSHIP_CHECK_721) {
            (address owner, address token, uint256 id) = abi.decode(inputs, (address, address, uint256));
            success = (ERC721(token).ownerOf(id) == owner);
            if (!success) output = abi.encodeWithSignature('InvalidOwnerERC721()');
        } else if (command == Commands.OWNERSHIP_CHECK_1155) {
            (address owner, address token, uint256 id, uint256 minBalance) =
                abi.decode(inputs, (address, address, uint256, uint256));
            success = (ERC1155(token).balanceOf(owner, id) >= minBalance);
            if (!success) output = abi.encodeWithSignature('InvalidOwnerERC1155()');
        } else if (command == Commands.CRYPTOPUNKS) {
            (uint256 punkId, address recipient, uint256 value) = abi.decode(inputs, (uint256, address, uint256));
            try ICryptoPunksMarket(Constants.CRYPTOPUNKS).buyPunk{value: value}(punkId) {
                ICryptoPunksMarket(Constants.CRYPTOPUNKS).transferPunk(recipient, punkId);
            } catch {
                success = false;
            }
        } else {
            revert InvalidCommandType(command);
        }
    }

    function callAndTransfer721(bytes memory inputs, address protocol)
        internal
        returns (bool success, bytes memory output)
    {
        (uint256 value, bytes memory data, address recipient, address token, uint256 id) =
            abi.decode(inputs, (uint256, bytes, address, address, uint256));
        (success, output) = protocol.call{value: value}(data);
        if (success) ERC721(token).safeTransferFrom(address(this), recipient, id);
    }

    function callAndTransfer1155(bytes memory inputs, address protocol)
        internal
        returns (bool success, bytes memory output)
    {
        (uint256 value, bytes memory data, address recipient, address token, uint256 id, uint256 amount) =
            abi.decode(inputs, (uint256, bytes, address, address, uint256, uint256));
        (success, output) = protocol.call{value: value}(data);
        if (success) ERC1155(token).safeTransferFrom(address(this), recipient, id, amount, new bytes(0));
    }
}