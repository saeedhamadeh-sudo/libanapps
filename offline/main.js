// ============================================================
//  LibanApps Local — برنامج الكمبيوتر (Windows)
//  · بيشغّل السيرفر المحلي وقاعدة البيانات على هالكمبيوتر
//  · بيفتح برنامج الألمنيوم / التجارة بنافذة
//  · لما تسكّر النافذة بيضل شغّال بجنب الساعة (حتى يضل الوصول من برّا شغّال)
//  · طباعة صامتة على طابعات الجهاز (نفس نسخة LibanApps للكمبيوتر)
// ============================================================
'use strict';
const { app, BrowserWindow, ipcMain, session, shell, Tray, Menu, nativeImage, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const { start } = require('./server');

const PORT = 47801;
const BASE = 'http://127.0.0.1:' + PORT;
let win = null, tray = null, srv = null, quitting = false;

if(!app.requestSingleInstanceLock()){ app.quit(); }
app.on('second-instance', () => showWindow());

function res(...p){ return app.isPackaged ? path.join(process.resourcesPath, ...p) : path.join(__dirname, ...p); }
function iconPath(){ const p = res('build', 'icon.png'); return fs.existsSync(p) ? p : path.join(__dirname, 'build', 'icon.png'); }

function createWindow(hidden){
  win = new BrowserWindow({
    width: 1366, height: 820, minWidth: 900, minHeight: 600, show: !hidden,
    title: 'LibanApps', autoHideMenuBar: true, icon: iconPath(),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false }
  });
  if(!hidden) win.maximize();
  win.loadURL(BASE + '/');
  win.webContents.setWindowOpenHandler(({ url }) => {
    if(url.startsWith(BASE) || url.startsWith('about:blank')) return { action: 'allow' };
    shell.openExternal(url);
    return { action: 'deny' };
  });
  win.on('close', e => {
    if(quitting) return;
    e.preventDefault(); win.hide();
    if(tray && !app._hintShown){ app._hintShown = true;
      try{ tray.displayBalloon({ title: 'LibanApps', content: 'البرنامج بعدو شغّال هون حتى يضل الوصول من برّا والنسخ الاحتياطي شغّالين.' }); }catch(e){} }
  });
}
function showWindow(){
  if(!win || win.isDestroyed()) createWindow(false);
  if(win.isMinimized()) win.restore();
  if(!win.isVisible()){ win.show(); win.maximize(); }
  win.focus();
}
function open(p){ showWindow(); win.loadURL(BASE + p); }

function createTray(){
  const img = nativeImage.createFromPath(iconPath()).resize({ width: 16, height: 16 });
  tray = new Tray(img);
  tray.setToolTip('LibanApps — البيانات على هالكمبيوتر');
  const startup = app.getLoginItemSettings().openAtLogin;
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'افتح LibanApps', click: () => open('/') },
    { label: 'محاسبة التجارة', click: () => open('/trade') },
    { label: 'محاسبة الألمنيوم', click: () => open('/alum') },
    { type: 'separator' },
    { label: 'الوصول من برّا', click: () => open('/#remote') },
    { label: 'النسخ الاحتياطي', click: () => open('/#backup') },
    { label: 'يشتغل مع تشغيل الكمبيوتر', type: 'checkbox', checked: startup,
      click: m => app.setLoginItemSettings({ openAtLogin: m.checked, args: ['--hidden'] }) },
    { type: 'separator' },
    { label: 'خروج', click: () => { quitting = true; app.quit(); } }
  ]));
  tray.on('double-click', () => showWindow());
}

// طابعة USB (WebUSB) والأذونات — بس لصفحات البرنامج المحلي
function allowDevices(){
  const ses = session.defaultSession;
  const ours = origin => { try{ return new URL(origin).origin === BASE; }catch(e){ return false; } };
  ses.setPermissionCheckHandler((wc, permission, origin) => ours(origin));
  ses.setPermissionRequestHandler((wc, permission, cb, details) => cb(ours(details.requestingUrl || '')));
  ses.setDevicePermissionHandler(details => ours(details.origin));
  ses.on('select-usb-device', (event, details, callback) => {
    event.preventDefault();
    callback(details.deviceList && details.deviceList[0] ? details.deviceList[0].deviceId : '');
  });
}

ipcMain.handle('printers:list', async event => {
  const list = await event.sender.getPrintersAsync();
  return list.map(p => ({ name: p.name, displayName: p.displayName || p.name, isDefault: !!p.isDefault }));
});
ipcMain.handle('print:silent', (event, opts) => new Promise(resolve => {
  const o = opts || {};
  const options = { silent: true, printBackground: true, margins: { marginType: 'none' } };
  if(o.deviceName) options.deviceName = o.deviceName;
  if(o.format !== 'a4') options.pageSize = { width: 80000, height: 297000 };
  else options.pageSize = 'A4';
  event.sender.print(options, (success, failureReason) => resolve(success ? { ok: true } : { ok: false, error: failureReason || 'print failed' }));
}));

app.whenReady().then(async () => {
  const hidden = process.argv.includes('--hidden');
  const appDir = [res('app-web'), path.join(__dirname, 'app'), path.join(__dirname, '..', 'public')].find(p => fs.existsSync(path.join(p, 'app-trade.html')));
  try{
    srv = await start({
      port: PORT, desktop: true,
      dataDir: path.join(app.getPath('userData'), 'data'),
      backupDir: path.join(app.getPath('documents'), 'LibanApps Backups'),
      appDir, webDir: path.join(__dirname, 'web'),
      cloudflaredPath: res('bin', process.platform === 'win32' ? 'cloudflared.exe' : 'cloudflared'),
      openPath: p => shell.openPath(p),
      // تحديث البرنامج نفسو: منفتح ملف التثبيت الجديد ومنسكّر (البيانات بمجلد منفصل، ما بتتأثر)
      runInstaller: (file, silent) => {
        if(silent){
          // تركيب صامت بلا أسئلة، وبعدين البرنامج بيرجع يفتح لحالو (--force-run)
          try{ require('child_process').spawn(file, ['/S', '--updated', '--force-run'], { detached: true, stdio: 'ignore' }).unref(); }
          catch(e){ return; }
          setTimeout(() => { quitting = true; app.quit(); }, 500);
        } else {
          shell.openPath(file).then(() => setTimeout(() => { quitting = true; app.quit(); }, 1500));
        }
      }
    });
  }catch(e){
    // البورت مستعمل: إذا يلي ماسكو هو LibanApps نفسو (نسخة تانية شغّالة) منفتح نافذة عليه بدل الخطأ
    let ours = false;
    if(e && e.code === 'EADDRINUSE'){
      try{ const r = await fetch(BASE + '/local-api/status', { signal: AbortSignal.timeout(3000) }); const j = await r.json(); ours = !!(j && j.version); }catch(x){}
    }
    if(!ours){
      dialog.showErrorBox('LibanApps', e && e.code === 'EADDRINUSE'
        ? 'البورت ' + PORT + ' مستعمل من برنامج تاني. سكّر البرنامج التاني أو اعمل Restart للكمبيوتر.'
        : 'تعذّر تشغيل البرنامج: ' + (e && e.message || e));
      app.exit(1); return;
    }
    srv = null;
  }
  // أول تشغيل: منخلّيه يشتغل مع ويندوز (الوصول من برّا بيحتاج البرنامج شغّال)
  if(srv && !srv.store.kvGet('login_item_set', false)){
    app.setLoginItemSettings({ openAtLogin: true, args: ['--hidden'] });
    srv.store.kvSet('login_item_set', true);
  }
  // نسخة جديدة من البرنامج نزلت بالخلفية؟ منركّبها هلق قبل ما يبلّش الشغل
  if(srv && srv.updater.installPending()) return;
  allowDevices();
  createTray();
  createWindow(hidden);
});

// قبل الخروج: نسخة احتياطية سريعة إذا آخر نسخة قديمة، وبعدين منسكّر القاعدة
app.on('before-quit', e => {
  quitting = true;
  if(!srv || app._closing) return;
  e.preventDefault(); app._closing = true;
  const last = srv.store.kvGet('backup_last', null);
  const need = !last || Date.now() - last.at > 6 * 3600000;
  Promise.race([need ? srv.backup.run('on-quit') : Promise.resolve(), new Promise(r => setTimeout(r, 20000))])
    .finally(async () => { try{ await srv.stop(); }catch(x){} app.exit(0); });
});
app.on('window-all-closed', () => { /* بيضل شغّال بجنب الساعة */ });
