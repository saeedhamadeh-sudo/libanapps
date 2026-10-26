// يكشف للموقع قدرات الكمبيوتر: لائحة الطابعات والطباعة الصامتة (بلا نافذة)
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('libanappsDesktop', {
  isDesktop: true,
  version: '1.1.0',
  getPrinters: () => ipcRenderer.invoke('printers:list'),
  // opts: { deviceName: اسم الطابعة ('' = الافتراضية), format: 'thermal80' | 'a4' }
  silentPrint: (opts) => ipcRenderer.invoke('print:silent', opts || {})
});
