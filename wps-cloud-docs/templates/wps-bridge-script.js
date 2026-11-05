// ============================================================
// WPS 云文档桥接脚本 (Hermes Bridge Script) v4.2
// 更新：新增 write_grid 批量写入二维数组
// 通过 AirScript 脚本令牌外部调用，实现云文档读写
// 部署：WPS多维表格 → 脚本编辑器 → 新建脚本 → 粘贴保存
//       （必须添加「云文档API」服务，每个脚本单独添加！）
// 调用：POST webhook 链接 + Header: AirScript-Token: <你的令牌>
//       body: {"Context":{"argv":{"action":"list"}}}
// 操作：list 列出 / find_read 按名定位读 / read 读 / write 写 /
//       write_grid 批量写 / create 创建
// ============================================================

const argv = Context.argv || {};
const action = argv.action || 'list';
let result = {};

// 列出目录文件（返回完整 FileInfo）
function listDir(dirUrl, exts, count) {
  const opts = { includeExts: exts || ['et', 'ksheet', 'db', 'otl', 'wps', 'wpp'] };
  if (count) opts.count = Number(count);
  if (dirUrl) opts.dirUrl = dirUrl;
  return KSDrive.listFiles(opts);
}

// 按文件名在目录中定位（返回完整 FileInfo 或 null）
function findFile(dirUrl, name, exts) {
  const list = listDir(dirUrl, exts, 100);
  for (let i = 0; i < list.files.length; i++) {
    if (list.files[i].fileName === name) return list.files[i];
  }
  return null;
}

try {
  if (action === 'list') {
    // 列出目录文件
    const list = listDir(argv.dirUrl, (argv.exts || 'et,ksheet,db,otl,wps,wpp').split(','), argv.count);
    result.files = list.files.map(function (f) {
      return { name: f.fileName, fileId: f.fileId, createTime: f.createTime, updateTime: f.updateTime };
    });
    result.nextOffset = list.nextOffset;
    result.count = list.files.length;
  } else if (action === 'find_read') {
    // 按文件名在目录中定位并读取内容（dirUrl + name 必填）
    if (!argv.name) throw new Error('find_read 需要 name 参数');
    const target = findFile(argv.dirUrl, argv.name, (argv.exts || 'et,ksheet,db,otl,wps,wpp').split(','));
    if (!target) {
      result.error = '未找到文件: ' + argv.name;
    } else {
      const file = KSDrive.openFile(target); // 传入完整 FileInfo
      try {
        const sheet = argv.sheet ? file.Application.Sheets(argv.sheet) : file.Application.ActiveSheet;
        if (argv.range) {
          const rng = sheet.Range(argv.range);
          result.data = rng.Value;
          result.range = argv.range;
        } else {
          const used = sheet.UsedRange;
          result.data = used.Value;
          result.range = used.Address;
          result.fileId = target.fileId;
        }
      } finally {
        file.close();
      }
    }
  } else if (action === 'read') {
    // 读取：argv.url（分享链接）或 argv.fileId（配合 name）
    const info = argv.fileId ? { fileId: argv.fileId, fileName: argv.name || '' } : argv.url;
    const file = KSDrive.openFile(info);
    try {
      const sheet = argv.sheet ? file.Application.Sheets(argv.sheet) : file.Application.ActiveSheet;
      if (argv.range) {
        result.data = sheet.Range(argv.range).Value;
        result.range = argv.range;
      } else {
        const used = sheet.UsedRange;
        result.data = used.Value;
        result.range = used.Address;
      }
    } finally {
      file.close();
    }
  } else if (action === 'write') {
    // 写入：argv.url 或 argv.fileId + argv.range + argv.value
    if (argv.range === undefined || argv.value === undefined) {
      throw new Error('write 需要 range + value 参数');
    }
    const info = argv.fileId ? { fileId: argv.fileId, fileName: argv.name || '' } : argv.url;
    const file = KSDrive.openFile(info);
    try {
      const sheet = argv.sheet ? file.Application.Sheets(argv.sheet) : file.Application.ActiveSheet;
      sheet.Range(argv.range).Value = argv.value;
      result.ok = true;
      result.range = argv.range;
      result.value = argv.value;
    } finally {
      file.close();
    }
  } else if (action === 'write_grid') {
    // 批量写入二维数组：argv.url 或 argv.fileId + argv.range + argv.grid
    if (argv.range === undefined || !argv.grid || !Array.isArray(argv.grid)) {
      throw new Error('write_grid 需要 range + grid(二维数组) 参数');
    }
    const info = argv.fileId ? { fileId: argv.fileId, fileName: argv.name || '' } : argv.url;
    const file = KSDrive.openFile(info);
    try {
      const sheet = argv.sheet ? file.Application.Sheets(argv.sheet) : file.Application.ActiveSheet;
      sheet.Range(argv.range).Value = argv.grid;
      result.ok = true;
      result.range = argv.range;
      result.rows = argv.grid.length;
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
    result.error = '未知操作: ' + action + ' (支持: list/find_read/read/write/write_grid/create)';
  }
} catch (e) {
  result.error = String(e && e.message ? e.message : e);
}

return result;
