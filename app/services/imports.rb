# Deterministic ingestion pipeline for uploaded extratos/faturas (.plans/auto). The parsers and
# proposal builders live under this namespace; the money law is the house rule — the LLM never
# computes cents, Ruby does (Money.to_cents for pt-BR strings, BigDecimal for spec'd dot-decimal).
module Imports
  Error             = Class.new(StandardError)
  ParseError        = Class.new(Error)   # → error_code: parse_failed
  PasswordProtected = Class.new(Error)   # → error_code: password_protected
  TooLarge          = Class.new(Error)   # → error_code: too_large (PDF page cap)

  module_function

  # Brazilian bank exports are UTF-8 or Latin-1 — nothing else observed. Decode once, before any
  # parser runs; strip a UTF-8 BOM.
  def decode(bytes)
    s = bytes.to_s.dup.force_encoding(Encoding::UTF_8)
    s = bytes.to_s.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8) unless s.valid_encoding?
    s.delete_prefix("﻿")
  end

  def strip_accents(text)
    text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "")
  end

  # Digits only (agency/account normalization for matching).
  def digits(value) = value.to_s.gsub(/\D/, "")

  # Digits, leading zeros stripped — "01003172-6" ≡ "1003172-6" ≡ "10031726".
  def normalize_account(value) = digits(value).sub(/\A0+/, "")
end
