fs       = require 'fs'
path     = require 'path'
os       = require 'os'
wrench   = require 'wrench'
GitHub   = require 'github-releases'
Progress = require 'progress'
gutil    = require 'gulp-util'
PluginError = gutil.PluginError

getApmPath = ->
  apmPath = path.join 'apm', 'node_modules', 'atom-package-manager', 'bin', 'apm'
  apmPath = 'apm' unless fs.existsSync(apmPath) and fs.statSync(apmPath).isFile

  if process is 'win32' then "#{apmPath}.cmd" else apmPath

getCurrentAtomShellVersion = (outputDir) ->
  versionPath = path.join outputDir, 'version'
  if fs.existsSync(versionPath) and fs.statSync(versionPath).isFile
    fs.readFileSync(versionPath).toString().trim()
  else
    null

isAtomShellVersionCached = (downloadDir, version) ->
  fs.existsSync(path.join(downloadDir, version, 'version')) and fs.statSync(path.join(downloadDir, version, 'version')).isFile

installAtomShell = (outputDir, downloadDir, version) ->
  wrench.copyDirSyncRecursive path.join(downloadDir, version), outputDir,
    forceDelete: true
    excludeHiddenUnix: false
    inflateSymlinks: false

unzipAtomShell = (zipPath, callback) ->
  gutil.log 'Unzipping atom-shell.'
  directoryPath = path.dirname zipPath

  if process.platform is 'darwin'
    # The zip archive of darwin build contains symbol links, only the "unzip"
    # command can handle it correctly.
    spawn {cmd: 'unzip', args: [zipPath, '-d', directoryPath]}, (error) ->
      fs.unlinkSync zipPath
      callback error
  else
    DecompressZip = require('decompress-zip')
    unzipper = new DecompressZip(zipPath)
    unzipper.on 'error', callback
    unzipper.on 'extract', (log) ->
      fs.closeSync unzipper.fd
      fs.unlinkSync zipPath
      callback null
    unzipper.extract(path: directoryPath)

saveAtomShellToCache = (inputStream, outputDir, downloadDir, version, callback) ->
  wrench.mkdirSyncRecursive path.join downloadDir, version
  cacheFile = path.join downloadDir, version, 'atom-shell.zip'

  unless process.platform is 'win32'
    len = parseInt(inputStream.headers['content-length'], 10)
    progress = new Progress('downloading [:bar] :percent :etas', {complete: '=', incomplete: ' ', width: 20, total: len})

  outputStream = fs.createWriteStream(cacheFile)
  inputStream.pipe outputStream
  inputStream.on 'error', callback
  outputStream.on 'error', callback
  outputStream.on 'close', unzipAtomShell.bind this, cacheFile, callback
  inputStream.on 'data', (chunk) ->
    return if process.platform is 'win32'

    process.stdout.clearLine?()
    process.stdout.cursorTo?(0)
    progress.tick(chunk.length)

rebuildNativeModules = (apm, previousVersion, currentVersion) ->
  if currentVersion isnt previousVersion
    gutil.log "gulp-download-atom-shell", "Rebuilding native modules for new atom-shell version #{currentVersion}."
    apm ?= getApmPath()
    spawn {cmd: apm, args: ['rebuild']}

module.exports = (options) ->
  options = {} unless options?

  if not (options.version? and options.outputDir?)
    throw new PluginError "gulp-download-atom-shell", "version and outputDir option must be given!"

  {version, outputDir, downloadDir, symbols, rebuild, apm} = options
  version = "v#{version}"
  downloadDir ?= path.join os.tmpdir(), 'downloaded-atom-shell'
  symbols ?= false
  rebuild ?= false
  apm ?= getApmPath()

  # Do nothing if it's the expected version.
  currentAtomShellVersion = getCurrentAtomShellVersion outputDir
  return if currentAtomShellVersion is version

  # Try find the cached one.
  if isAtomShellVersionCached downloadDir, version
    gutil.log "gulp-download-atom-shell", "Installing cached atom-shell #{version}."
    installAtomShell outputDir, downloadDir, version
    rebuildNativeModules apm, currentAtomShellVersion, version
  else
    # Request the assets.
    github = new GitHub({repo: 'atom/atom-shell'})
    github.getReleases tag_name: version, (error, releases) ->
      unless releases?.length > 0
        throw new PluginError "gulp-download-atom-shell", "Cannot find atom-shell #{version} from GitHub"

      # Which file to download
      filename =
        if symbols
          "atom-shell-#{version}-#{process.platform}-symbols.zip"
        else
          "atom-shell-#{version}-#{process.platform}.zip"

      # Find the asset of current platform.
      found = false
      for asset in releases[0].assets when asset.name is filename
        found = true
        github.downloadAsset asset, (error, inputStream) ->
          if error?
            throw new PluginError "gulp-download-atom-shell", "Cannot download atom-shell #{version}"

          # Save file to cache.
          gutil.log "gulp-download-atom-shell", "Downloading atom-shell #{version}."
          saveAtomShellToCache inputStream, outputDir, downloadDir, version, (error) ->
            if error?
              throw PluginError "Failed to download atom-shell #{version}"

            gutil.log "gulp-download-atom-shell", "Installing atom-shell #{version}."
            installAtomShell outputDir, downloadDir, version
            rebuildNativeModules apm, currentAtomShellVersion, version

      if not found
        throw new PluginError "gulp-download-atom-shell", "Cannot find #{filename} in atom-shell #{version} release"