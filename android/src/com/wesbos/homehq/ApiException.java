package com.wesbos.homehq;

final class ApiException extends Exception {
  final int status;
  final String code;

  private ApiException(int status, String code, String message) {
    super(message);
    this.status = status;
    this.code = code;
  }

  static ApiException badRequest(String message) {
    return new ApiException(400, "bad_request", message);
  }

  static ApiException unauthorized(String message) {
    return new ApiException(401, "unauthorized", message);
  }

  static ApiException forbidden(String message) {
    return new ApiException(403, "forbidden", message);
  }

  static ApiException notFound(String message) {
    return new ApiException(404, "not_found", message);
  }

  static ApiException conflict(String message) {
    return new ApiException(409, "conflict", message);
  }

  static ApiException pairingBusy(String message) {
    return new ApiException(409, "pairing_busy", message);
  }

  static ApiException gone(String message) {
    return new ApiException(410, "gone", message);
  }

  static ApiException tooLarge(String message) {
    return new ApiException(413, "too_large", message);
  }

  static ApiException rateLimited(String message) {
    return new ApiException(429, "rate_limited", message);
  }

  static ApiException unsaved() {
    return new ApiException(500, "internal", "The frame could not save this change. Its storage may be full.");
  }
}
