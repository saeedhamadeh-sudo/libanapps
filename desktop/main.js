// LibanApps للكمبيوتر — بيفتح libanapps.com وبيضيف طباعة صامتة على طابعات الجهاز
const { app, BrowserWindow, ipcMain, session, shell } = require('electron');
const path = require('path');

const START_URL = 'https://libanapps.com';
let win;

function createWindow(){
  win = new BrowserWindow({
    width: 1366, height: 820, minWidth: 900, minHeight: 600,
    title: 'LibanApps',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  win.maximize();
  win.loadURL(START_URL);
  // الروابط الخارجية (واتساب، خرائط...) بتفتح بالمتصفح العادي
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith(START_URL) || url.startsWith('about:blank')) return { action: 'allow' };
    shell.openExternal(url);
    return { action: 'deny' };
  });
}

// طابعة USB (WebUSB) لفتح الدرج والطباعة المباشرة — نفس سماحيات النسخة السابقة
function allowDevices(){
  const ses = session.defaultSession;
  const ours = (origin) => { try { return new URL(origin).hostname.endsWith('libanapps.com'); } catch (e) { return false; } };
  ses.setPermissionCheckHandler((wc, permission, origin) => ours(origin));
  ses.setDevicePermissionHandler((details) => ours(details.origin));
  ses.on('select-usb-device', (event, details, callback) => {
    event.preventDefault();
    callback(details.deviceList && details.deviceList[0] ? details.deviceList[0].deviceId : '');
  });
}

ipcMain.handle('printers:list', async (event) => {
  const list = await event.sender.getPrintersAsync();
  return list.map(p => ({ name: p.name, displayName: p.displayName || p.name, isDefault: !!p.isDefault }));
});

ipcMain.handle('print:silent', (event, opts) => new Promise((resolve) => {
  const o = opts || {};
  const options = {
    silent: true,
    printBackground: true,
    margins: { marginType: 'none' }
  };
  if (o.deviceName) options.deviceName = o.deviceName;
  // 80 ملم: عرض الورق 80mm وطول طويل كفاية (الطابعة الحرارية بتقص عند نهاية الفاتورة)
  if (o.format !== 'a4') options.pageSize = { width: 80000, height: 297000 };
  else options.pageSize = 'A4';
  event.sender.print(options, (success, failureReason) => {
    resolve(success ? { ok: true } : { ok: false, error: failureReason || 'print failed' });
  });
}));

app.whenReady().then(() => {
  allowDevices();
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
