/**
 * Multi-chain address encoding — converts EVM, Tron, and Solana addresses to hex bytes.
 */
import bs58 from "bs58";
import { tronToHex } from "./tronHelper";

/**
 * Convert any address format to hex bytes.
 * - EVM address (0x prefix): return as-is lowercase
 * - Tron address (T prefix, 34 chars, 0x41 byte): convert via tronToHex
 * - Solana/other base58 address: base58 decode to full bytes
 * @param addr - address in any supported format
 */
export function addressToHex(addr: string): string {
    if (addr.startsWith("0x")) {
        return addr.toLowerCase();
    }

    if (isTronAddress(addr)) {
        return tronToHex(addr);
    }

    if (isBase58(addr)) {
        const decoded = bs58.decode(addr);
        return "0x" + Buffer.from(decoded).toString("hex");
    }

    throw new Error(`Unknown address format: ${addr}`);
}

/** Check if a string is valid base58 encoding. */
export function isBase58(addr: string): boolean {
    const base58Chars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    for (const char of addr) {
        if (!base58Chars.includes(char)) {
            return false;
        }
    }
    return true;
}

/** Check if address is Tron format (T prefix, 34 chars, 0x41 first byte after decode). */
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

/** Check if chain name is Solana. */
export function isSolanaChain(chainName: string): boolean {
    return chainName === "Sol" || chainName === "sol_test";
}
