package com.wesbos.homehq;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class TccSecret {
  private static final String ALIAS = "skylit_thermostat_v1";

  private TccSecret() {}

  private static SecretKey key() throws Exception {
    KeyStore store = KeyStore.getInstance("AndroidKeyStore");
    store.load(null);
    if (store.containsAlias(ALIAS)) return (SecretKey) store.getKey(ALIAS, null);
    KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
    generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setRandomizedEncryptionRequired(true).build());
    return generator.generateKey();
  }

  static String seal(String value, String account) throws Exception {
    Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
    cipher.init(Cipher.ENCRYPT_MODE, key());
    cipher.updateAAD(account.getBytes(StandardCharsets.UTF_8));
    byte[] iv = cipher.getIV();
    byte[] body = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
    byte[] output = new byte[iv.length + body.length];
    System.arraycopy(iv, 0, output, 0, iv.length);
    System.arraycopy(body, 0, output, iv.length, body.length);
    return Base64.encodeToString(output, Base64.NO_WRAP);
  }

  static String open(String encoded, String account) throws Exception {
    byte[] input = Base64.decode(encoded, Base64.NO_WRAP);
    if (input.length < 29) throw new IllegalArgumentException("Invalid encrypted value");
    Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
    cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, input, 0, 12));
    cipher.updateAAD(account.getBytes(StandardCharsets.UTF_8));
    return new String(cipher.doFinal(input, 12, input.length - 12), StandardCharsets.UTF_8);
  }

  static void forget() throws Exception {
    KeyStore store = KeyStore.getInstance("AndroidKeyStore");
    store.load(null);
    if (store.containsAlias(ALIAS)) store.deleteEntry(ALIAS);
  }
}
