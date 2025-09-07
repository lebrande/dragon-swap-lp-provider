import { Address } from "viem";
import { useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

export const useApproveUsdcForVault = () => {
  const { writeContractAsync: approveAsync, isMining } = useScaffoldWriteContract({ contractName: "USDC" });

  const approve = async (vaultAddress: Address, amount: bigint) => {
    return approveAsync({ functionName: "approve", args: [vaultAddress, amount] } as any);
  };

  return { approve, isApproving: isMining };
};
