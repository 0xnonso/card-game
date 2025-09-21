// bit layout: [ s s s | n n n n n ]
// shape: 0..5  (0=Circle, 1=Cross, 2=Triangle, 3=Square, 4=Star, 5=Whot)
// number: 0..31 (Whot uses 20)

// Standard Whot 54-card deck (order: Circle, Triangle, Cross, Square, Star, 5×Whot-20)
export const WHOT_DECK: Uint8Array = Uint8Array.of(
  // Circle (shape 0): nums 1,2,3,4,5,7,8,10,11,12,13,14
  1,2,3,4,5,7,8,10,11,12,13,14,
  // Triangle (shape 2 → +64): same numbers + 64
  65,66,67,68,69,71,72,74,75,76,77,78,
  // Cross (shape 1 → +32): nums 1,2,3,5,7,10,11,13,14 + 32
  33,34,35,37,39,42,43,45,46,
  // Square (shape 3 → +96): same as Cross + 96
  97,98,99,101,103,106,107,109,110,
  // Star (shape 4 → +128): nums 1,2,3,4,5,7,8 + 128
  129,130,131,132,133,135,136,
  // Whot (shape 5 → +160) numbered 20
  180,180,180,180,180
);