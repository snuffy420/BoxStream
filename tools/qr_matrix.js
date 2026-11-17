// Prints a QR code's modules as JSON rows of 0/1 for build_about.py.
// Needs the "qrcode" npm package: npm install qrcode
const QRCode = require("qrcode");
const text = process.argv[2];
const qr = QRCode.create(text, { errorCorrectionLevel: "M" });
const size = qr.modules.size;
const rows = [];
for (let y = 0; y < size; y++) {
  let row = "";
  for (let x = 0; x < size; x++) row += qr.modules.get(y, x) ? "1" : "0";
  rows.push(row);
}
process.stdout.write(JSON.stringify(rows));
