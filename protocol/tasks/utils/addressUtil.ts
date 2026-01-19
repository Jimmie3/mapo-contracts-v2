import bs58 from "bs58"

/**
 * Convert address to hex bytes based on address format
 * - EVM address (0x prefix): return as-is (20 bytes)
 * - Tron address (T prefix, 34 chars): base58 decode, extract 20 bytes
 * - Solana/other base58 address: base58 decode to full bytes
 */
export function addressToHex(addr: string, toChain?: string): string {
    // Already hex format (EVM address)
    if (addr.startsWith('0x')) {
        return addr.toLowerCase();
    }

    // Tron address (starts with T, 34 chars)
    if (addr.startsWith('T') && addr.length === 34) {
        const decoded = bs58.decode(addr);
        // Tron format: 0x41 (1 byte) + address (20 bytes) + checksum (4 bytes)
        const addressBytes = decoded.slice(1, 21);
        return '0x' + Buffer.from(addressBytes).toString('hex');
    }

    // Solana or other base58 address
    if (isBase58(addr)) {
        const decoded = bs58.decode(addr);
        return '0x' + Buffer.from(decoded).toString('hex');
    }

    throw new Error(`Unknown address format: ${addr}`);
}

/**
 * Check if string is valid base58
 */
export function isBase58(addr: string): boolean {
    const base58Chars = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    for (const char of addr) {
        if (!base58Chars.includes(char)) {
            return false;
        }
    }
    return true;
}

/**
 * Check if address is Tron format (T prefix, 34 chars, base58)
 */
export function isTronAddress(addr: string): boolean {
    return addr.startsWith('T') && addr.length === 34 && isBase58(addr);
}

/**
 * Check if chain is Solana
 */
export function isSolanaChain(chainName: string): boolean {
    return chainName === 'Sol' || chainName === 'sol_test';
}