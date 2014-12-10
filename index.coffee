async    = require 'async'
fs       = require 'fs'
path     = require 'path'
os       = require 'os'
wrench   = require 'wrench'
GitHub   = require 'github-releases'
Progress = require 'progress'
gutil    = require 'gulp-util'
PluginError = gutil.PluginError

PLUGIN_NAME = "gulp-download-atom-shell"

spawn = (options, callback) ->
    childProcess = require 'child_process'
    stdout = []
    stderr = []
    error = null
    proc = childProcess.spawn options.cmd, options.args, options.opts
    proc.stdout.on 'data', (data) -> stdout.push data.toString()
    proc.stderr.on 'data', (data) -> stderr.push data.toString()
    proc.on 'exit', (code, signal) ->
      error = new Error(signal) if code != 0
      results = stderr: stderr.join(''), stdout: stdout.join(''), code: code
      gutil.log PLUGIN_NAME, gutil.colors.red(results.stderr) if code != 0
      callback error, results, code

isFile = (filePath) ->
  fs.existsSync(filePath) and fs.statSync(filePath).isFile

getApmPath = ->
  apmPath = path.join 'apm', 'node_modules', 'atom-package-manager', 'bin', 'apm'
  apmPath = 'apm' unless isFile apmPath

  if process.platform is 'win32' then "#{apmPath}.cmd" else apmPath

getCurrentAtomShellVersion = (outputDir) ->
  versionPath = path.join outputDir, 'version'
  if isFile versionPath
    fs.readFileSync(versionPath).toString().trim()
  else
    null

isAtomShellVersionCached = (downloadDir, version) ->
  isFile path.join(downloadDir, version, 'Atom.app')

installAtomShell = (outputDir, downloadDir, version) ->
  wrench.copyDirSyncRecursive path.join(downloadDir, version), outputDir,
    forceDelete: true
    excludeHiddenUnix: false
    inflateSymlinks: false

unzipAtomShell = (zipPath, callback) ->
  gutil.log PLUGIN_NAME, 'Unzipping atom-shell.'
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

module.exports = (options, cb) ->
  options = {} unless options?

  if not (options.version? and options.outputDir?)
    throw new PluginError PLUGIN_NAME, "version and outputDir option must be given!"

  {version, outputDir, downloadDir, symbols, rebuild, apm} = options
  version = "v#{version}"
  downloadDir ?= path.join os.tmpdir(), 'downloaded-atom-shell'
  symbols ?= false
  rebuild ?= false
  apm ?= getApmPath()

  # Do nothing if it's the expected version.
  currentAtomShellVersion = getCurrentAtomShellVersion outputDir
  outputAtom = path.join(outputDir, 'Atom.app')
  return cb() if ((currentAtomShellVersion is version) && isFile(outputAtom))

  async.series [
      # Try find the cached one, if not then download.
      (callback) ->
        if not isAtomShellVersionCached downloadDir, version
          # Request the assets.
          github = new GitHub({repo: 'atom/atom-shell'})
          github.getReleases tag_name: version, (error, releases) ->
            unless releases?.length > 0
              callback new Error "Cannot find atom-shell #{version} from GitHub"


            # Decide which arch to download:
            # Windows: 32bit
            # Linux: Current platform's arch
            # Mac: 64bit
            arch =
              switch process.platform
                when 'win32' then 'ia32'
                when 'darwin' then 'x64'
                else process.arch

            # Which file to download
            filename =
              if symbols
                "atom-shell-#{version}-#{process.platform}-#{arch}-symbols.zip"
              else
                "atom-shell-#{version}-#{process.platform}-#{arch}.zip"

            # Find the asset of current platform.
            found = false
            for asset in releases[0].assets when asset.name is filename
              found = true
              github.downloadAsset asset, (error, inputStream) ->
                if error?
                  callback new Error "Cannot download atom-shell #{version}"

                # Save file to cache.
                gutil.log PLUGIN_NAME, "Downloading atom-shell #{version}."
                saveAtomShellToCache inputStream, outputDir, downloadDir, version, (error) ->
                  if error?
                    callback new Error "Failed to download atom-shell #{version}"
                  else
                    callback()

            if not found
              callback new Error "Cannot find #{filename} in atom-shell #{version} release"
        else
          callback()

      (callback) ->
        installAtomShell outputDir, downloadDir, version

        callback()

      (callback) ->
        if rebuild and currentAtomShellVersion isnt version
          gutil.log PLUGIN_NAME, "Rebuilding native modules for new atom-shell version #{currentVersion}."
          apm ?= getApmPath()
          spawn {cmd: apm, args: ['rebuild']}, callback
        else
          callback()

    ], (error, results) ->
        if error
          throw new PluginError PLUGIN_NAME, error.message
        else
          cb()
