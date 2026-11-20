// POSIX printf %b accepts \0ddd octal escapes, including NUL bytes.
export function encodeKeyOctal(bytes) {
  return Array.from(bytes, byte => '\\0' + byte.toString(8).padStart(3, '0')).join('');
}
