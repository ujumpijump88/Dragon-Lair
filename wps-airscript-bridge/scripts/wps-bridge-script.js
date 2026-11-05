// ============================================================
// WPS 云文档桥接脚本 (Hermes Bridge Script) v2
// 通过 AirScript 脚本令牌外部调用，实现云文档读写
// 部署：WPS多维表格 → 脚本编辑器 → 新建脚本 → 粘贴保存
// 调用：POST webhook 链接 + Header: AirScript-Token: <你的令牌>
// ============================================================

const argv = Context.argv || {};
const action = argv.action || 'list';
let result = {};

// 解析目标文件：优先 fileId（list 返回的加密 id），其次 url（分享链接）
function resolveFile() {
  if (argv.fileId) return { fileId: argv.fileId, fileName: argv.name || '' };
  return argv.url;
}

try {
  if (action === 'list') {
    // 列出云文档（默认表格类：et/ksheet/db/ap）
    const exts = (argv.exts || 'et,ksheet,db,ap').split(',').filter(Boolean);
    const opts = { includeExts: exts };
    if (argv.count) opts.count = Number(argv.count);
    if (argv.offset) opts.offset = Number(argv.offset);
    if (argv.dirUrl) opts.dirUrl = argv.dirUrl;
    const list = KSDrive.listFiles(opts);
    result.files = list.files.map(function (f) {
      return { name: f.fileName, fileId: f.fileId, createTime: f.createTime, updateTime: f.updateTime };
    });
    result.nextOffset = list.nextOffset;
    result.count = list.files.length;
  } else if (action === 'read') {
    // 读取文档内容：argv.fileId 或 argv.url；argv.range 可选（默认已用区域）
    const file = KSDrive.openFile(resolveFile());
    try {
      const sheet = argv.sheet ? file.Application.Sheets(argv.sheet) : file.Application.ActiveSheet;
      if (argv.range) {
        result.data = sheet.Range(argv.range).Text;
        result.range = argv.range;
      } else {
        const used = sheet.UsedRange;
        result.data = used.Text;
        result.range = used.Address;
      }
    } finally {
      file.close();
    }
  } else if (action === 'write') {
    // 写入：argv.fileId 或 argv.url + argv.range + argv.value
    if (argv.range === undefined || argv.value === undefined) {
      throw new Error('write 需要 range + value 参数');
    }
    const file = KSDrive.openFile(resolveFile());
    try {
      const sheet = argv.sheet ? file.Application.Sheets(argv.sheet) : file.Application.ActiveSheet;
      sheet.Range(argv.range).Value = argv.value;
      result.ok = true;
      result.range = argv.range;
      result.value = argv.value;
    } finally {
      file.close();
    }
  } else if (action === 'create') {
    // 创建新文档
    const typeMap = { ET: KSDrive.FileType.ET, KSheet: KSDrive.FileType.KSheet, DB: KSDrive.FileType.DB, AP: KSDrive.FileType.AP };
    const type = typeMap[argv.type] || KSDrive.FileType.KSheet;
    const createOpts = { name: argv.name || 'Hermes新建文档' };
    if (argv.dirUrl) createOpts.dirUrl = argv.dirUrl;
    if (argv.source) createOpts.source = argv.source;
    result.url = KSDrive.createFile(type, createOpts);
    result.ok = true;
  } else {
    result.error = '未知操作: ' + action + ' (支持: list/read/write/create)';
  }
} catch (e) {
  result.error = String(e && e.message ? e.message : e);
}

return result;
