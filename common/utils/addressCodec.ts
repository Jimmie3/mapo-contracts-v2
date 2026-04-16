import bs58 from "bs58";

/**
 * Convert address to hex bytes based on address format
 * - EVM address (0x prefix): return as-is (20 bytes)
 * - Tron address (T prefix, 34 chars): base58 decode, extract 20 bytes
 * - Solana/other base58 address: base58 decode to full bytes
 */
export function addressToHex(addr: string): string {
    if (addr.startsWith("0x")) {
        return addr.toLowerCase();
    }

    if (isTronAddress(addr)) {
        const decoded = bs58.decode(addr);
        // Tron format: 0x41 (1 byte) + address (20 bytes) + checksum (4 bytes)
        const addressBytes = decoded.slice(1, 21);
        return "0x" + Buffer.from(addressBytes).toString("hex");
    }

    if (isBase58(addr)) {
        const decoded = bs58.decode(addr);
        return "0x" + Buffer.from(decoded).toString("hex");
    }

    throw new Error(`Unknown address format: ${addr}`);
}

export function isBase58(addr: string): boolean {
    const base58Chars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    for (const char of addr) {
        if (!base58Chars.includes(char)) {
            return false;
        }
    }
    return true;
}

export function isTronAddress(addr: string): boolean {
    if (!addr.startsWith("T") || addr.length !== 34 || !isBase58(addr)) return false;
    try {
        const decoded = bs58.decode(addr);
        // Tron: 0x41 (1 byte) + address (20 bytes) + checksum (4 bytes) = 25 bytes
        return decoded.length === 25 && decoded[0] === 0x41;
    } catch {
        return false;
    }
}

export function isSolanaChain(chainName: string): boolean {
    return chainName === "Sol" || chainName === "sol_test";
}
