import hashlib

import pytest

from app import crypto

TEST_MNEMONIC = " ".join(["abandon"] * 11 + ["about"])


def test_rfc6979_known_vector():
    # Widely used secp256k1 RFC6979 vector: key = 1, sha256("Satoshi Nakamoto")
    sig = crypto.sign_digest((1).to_bytes(32, "big"), hashlib.sha256(b"Satoshi Nakamoto").digest())
    assert sig[:32].hex() == "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8"
    assert sig[32:64].hex() == "2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"


def test_sign_and_recover_roundtrip():
    priv = hashlib.sha256(b"test").digest()
    digest = hashlib.sha256(b"hello").digest()
    sig = crypto.sign_digest(priv, digest)
    assert len(sig) == 65 and sig[64] in (27, 28)
    assert crypto.signer_address(digest, sig) == crypto.address_from_private(priv)
    # tampered digest -> different signer
    assert crypto.signer_address(hashlib.sha256(b"other").digest(), sig) != crypto.address_from_private(priv)


def test_cross_platform_vector():
    """Same vector is asserted in mobile/test/signer_test.dart."""
    priv = hashlib.sha256(b"test").digest()
    sig = crypto.sign_digest(priv, hashlib.sha256(b"hello").digest())
    assert sig.hex() == ("d10a1041283dd120e8b539fad17b8c687dbb2a1792bf814409d15b6a95c921c0"
                         "3327a135389e8028013a33888ac4a20fe72793e0eff71cff9edc87b290b734451b")


def test_high_s_rejected():
    priv = hashlib.sha256(b"test").digest()
    digest = hashlib.sha256(b"hello").digest()
    sig = crypto.sign_digest(priv, digest)
    s = int.from_bytes(sig[32:64], "big")
    high = sig[:32] + (crypto.N - s).to_bytes(32, "big") + bytes([sig[64] ^ 1])
    assert crypto.signer_address(digest, high) is None


def test_mnemonic_derivation():
    assert crypto.address_from_private(crypto.private_key_from_mnemonic(TEST_MNEMONIC)) == \
        "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"
    assert crypto.address_from_private(crypto.private_key_from_mnemonic(TEST_MNEMONIC, 1)) == \
        "TSeJkUh4Qv67VNFwY8LaAxERygNdy6NQZK"


def test_matches_cryptography_library():
    ec = pytest.importorskip("cryptography.hazmat.primitives.asymmetric.ec")
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import utils
    priv = hashlib.sha256(b"k").digest()
    digest = hashlib.sha256(b"m").digest()
    sig = crypto.sign_digest(priv, digest)
    x, y = crypto.public_key(priv)
    pub = ec.EllipticCurvePublicNumbers(x, y, ec.SECP256K1()).public_key()
    der = utils.encode_dss_signature(int.from_bytes(sig[:32], "big"), int.from_bytes(sig[32:64], "big"))
    pub.verify(der, digest, ec.ECDSA(utils.Prehashed(hashes.SHA256())))
