// SPDX-License-Identifier: UNKNOWN
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/blast/IBlast.sol";
import "../interfaces/blast/IBlastPoints.sol";
import "./Errors.sol";

abstract contract BlastYield is Initializable {
    function __BlastYield_init(address owner) internal onlyInitializing {
        if(
            block.chainid == 81457 || // Mainnet
            block.chainid == 168587773 // Sepolia Testnet
        ) {
            IBlast blastYield = IBlast(0x4300000000000000000000000000000000000002);

            blastYield.configureClaimableYield();
            blastYield.configureClaimableGas();
            blastYield.configureGovernor(owner);

            if(block.chainid == 81457) // Mainnet
                IBlastPoints(0x2536FE9ab3F511540F2f9e2eC2A805005C3Dd800).configurePointsOperator(owner);
            else if(block.chainid == 168587773) // Testnet
                IBlastPoints(0x2fc95838c71e76ec69ff817983BFf17c710F34E0).configurePointsOperator(owner);
        }
    }
}
