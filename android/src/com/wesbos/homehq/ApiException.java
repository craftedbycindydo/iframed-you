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

  static ApiException notFound(String message) {
    return new ApiException(404, "not_found", message);
  }

  static ApiException conflict(String message) {
    return new ApiException(409, "conflict", message);
  }

  static ApiException tooLarge(String message) {
    return new ApiException(413, "too_large", message);
  }

  static ApiException rateLimited(String message) {
    return new ApiException(429, "rate_limited", message);
  }
}
