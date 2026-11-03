// يكشف للبرنامج قدرات الكمبيوتر: لائحة الطابعات والطباعة الصامتة (بلا نافذة)
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('libanappsDesktop', {
  isDesktop: true,
  isLocal: true,
  version: '2.0.0',
  getPrinters: () => ipcRenderer.invoke('printers:list'),
  // opts: { deviceName: اسم الطابعة ('' = الافتراضية), format: 'thermal80' | 'a4' }
  silentPrint: (opts) => ipcRenderer.invoke('print:silent', opts || {})
});
