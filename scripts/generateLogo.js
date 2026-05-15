const fs = require('fs');
const src = 'C:\\Users\\user\\BenzPackagingWeb\\BenzPackagingWeb\\assets\\images\\logo\\logo.png';
const dest = 'C:\\Users\\user\\benzdesk\\lib\\logoBase64.ts';
try {
  const b = fs.readFileSync(src).toString('base64');
  fs.writeFileSync(dest, 'export const BENZ_LOGO_BASE64 = "data:image/png;base64,' + b + '";\n');
  console.log('Success');
} catch (e) {
  console.error(e);
}
