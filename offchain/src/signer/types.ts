import type {Hex} from 'viem';

export interface KmsBackend {
  /** DER-encoded SubjectPublicKeyInfo of the secp256k1 key */
  getPublicKey(): Promise<Uint8Array>;
  /** DER-encoded ECDSA signature over a 32-byte digest */
  signDigest(digest: Hex): Promise<Uint8Array>;
}
