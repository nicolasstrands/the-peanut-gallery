const adjectives = [
  "Brave",
  "Clever",
  "Cosmic",
  "Dazzling",
  "Fierce",
  "Golden",
  "Jolly",
  "Lucky",
  "Mighty",
  "Nimble",
  "Quiet",
  "Swift",
];
const animalsAndColors = [
  "Badger",
  "Bear",
  "Blue",
  "Cardinal",
  "Coral",
  "Crimson",
  "Dolphin",
  "Fox",
  "Green",
  "Jaguar",
  "Koala",
  "Lynx",
  "Otter",
  "Panther",
  "Purple",
  "Raven",
  "Red",
  "Tiger",
  "Wolf",
  "Yellow",
];

export function participantNickname(fingerprint: string) {
  let hash = 2166136261;
  for (const character of fingerprint) {
    hash ^= character.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  const unsignedHash = hash >>> 0;
  return `${adjectives[unsignedHash % adjectives.length]}${animalsAndColors[Math.floor(unsignedHash / adjectives.length) % animalsAndColors.length]}`;
}
