// scripts/generate-promo-codes.js
// Generate unique promo codes for sideload users

const admin = require('firebase-admin');
const crypto = require('crypto');

// Initialize Firebase Admin
const serviceAccount = require('../service-account.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

/**
 * Generate a random alphanumeric code (excludes ambiguous characters)
 * @param {number} length - Length of code
 * @returns {string} - Random code
 */
function generateCode(length = 8) {
  // Exclude ambiguous characters: 0, O, 1, I, l
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  const bytes = crypto.randomBytes(length);
  
  for (let i = 0; i < length; i++) {
    code += chars[bytes[i] % chars.length];
  }
  
  return code;
}

/**
 * Check if a code already exists in Firestore
 * @param {string} code - Code to check
 * @returns {Promise<boolean>} - True if exists
 */
async function codeExists(code) {
  const doc = await db.collection('promo_codes').doc(code).get();
  return doc.exists;
}

/**
 * Generate unique promo code that doesn't exist yet
 * @param {number} length - Length of code
 * @returns {Promise<string>} - Unique code
 */
async function generateUniqueCode(length = 8) {
  let code;
  let attempts = 0;
  const maxAttempts = 100;
  
  do {
    code = generateCode(length);
    attempts++;
    
    if (attempts > maxAttempts) {
      throw new Error('Failed to generate unique code after max attempts');
    }
  } while (await codeExists(code));
  
  return code;
}

/**
 * Create a batch of promo codes
 * @param {number} count - Number of codes to generate
 * @param {string} type - 'premium' or 'proOffline'
 * @param {number|null} expiresInDays - Days until expiration (null = no expiration)
 * @param {string} description - Description for tracking
 * @returns {Promise<string[]>} - Array of generated codes
 */
async function createPromoBatch(count, type, expiresInDays = null, description = '') {
  console.log(`Generating ${count} ${type} codes...`);
  
  const codes = [];
  const batch = db.batch();
  let batchCount = 0;
  
  for (let i = 0; i < count; i++) {
    const code = await generateUniqueCode(8);
    codes.push(code);
    
    const data = {
      type,
      maxUses: 1, // Single use only
      usedBy: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: 'admin-script',
      description: description || `Batch generated ${type} code`,
      batchId: crypto.randomBytes(8).toString('hex'), // Track which batch this belongs to
    };
    
    if (expiresInDays) {
      const expiry = new Date();
      expiry.setDate(expiry.getDate() + expiresInDays);
      data.expiresAt = admin.firestore.Timestamp.fromDate(expiry);
    }
    
    const ref = db.collection('promo_codes').doc(code);
    batch.set(ref, data);
    batchCount++;
    
    // Firestore batch limit is 500 operations
    if (batchCount === 500) {
      await batch.commit();
      console.log(`  Committed ${codes.length} codes so far...`);
      batchCount = 0;
    }
    
    // Progress indicator
    if ((i + 1) % 10 === 0) {
      process.stdout.write(`\r  Progress: ${i + 1}/${count}`);
    }
  }
  
  // Commit remaining codes
  if (batchCount > 0) {
    await batch.commit();
  }
  
  console.log(`\n✓ Created ${codes.length} codes successfully!`);
  return codes;
}

/**
 * Save codes to a file for distribution
 * @param {string[]} codes - Array of codes
 * @param {string} filename - Output filename
 */
function saveCodesToFile(codes, filename) {
  const fs = require('fs');
  const path = require('path');
  
  const outputDir = path.join(__dirname, 'generated-codes');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir);
  }
  
  const filepath = path.join(outputDir, filename);
  const content = codes.join('\n');
  
  fs.writeFileSync(filepath, content);
  console.log(`\n✓ Codes saved to: ${filepath}`);
}

// Main execution
(async () => {
  try {
    const args = process.argv.slice(2);
    
    if (args.length === 0) {
      console.log('Usage: node generate-promo-codes.js <count> <type> [expiresInDays] [description]');
      console.log('');
      console.log('Examples:');
      console.log('  node generate-promo-codes.js 50 proOffline 90 "Q1 2025 sideload batch"');
      console.log('  node generate-promo-codes.js 10 premium 30 "Beta tester codes"');
      console.log('  node generate-promo-codes.js 100 proOffline null "No expiration batch"');
      process.exit(0);
    }
    
    const count = parseInt(args[0], 10);
    const type = args[1]; // 'premium' or 'proOffline'
    const expiresInDays = args[2] === 'null' ? null : parseInt(args[2], 10);
    const description = args[3] || `${type} batch ${new Date().toISOString().split('T')[0]}`;
    
    if (isNaN(count) || count < 1 || count > 1000) {
      console.error('Error: Count must be between 1 and 1000');
      process.exit(1);
    }
    
    if (type !== 'premium' && type !== 'proOffline') {
      console.error('Error: Type must be "premium" or "proOffline"');
      process.exit(1);
    }
    
    console.log('\n🎫 Promo Code Generator');
    console.log('=======================');
    console.log(`Type: ${type}`);
    console.log(`Count: ${count}`);
    console.log(`Expires: ${expiresInDays ? `${expiresInDays} days` : 'Never'}`);
    console.log(`Description: ${description}`);
    console.log('');
    
    const codes = await createPromoBatch(count, type, expiresInDays, description);
    
    // Save codes to file
    const timestamp = new Date().toISOString().split('T')[0];
    const filename = `${type}-codes-${timestamp}-${codes.length}.txt`;
    saveCodesToFile(codes, filename);
    
    console.log('\n✓ Done! Distribute these codes to sideload users.');
    console.log('  Each code is single-use and tracked in Firestore.');
    
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
})();
