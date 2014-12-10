# [gulp](http://gulpjs.com)-download-atom-shell
> Download [atom-shell](http://github.com/atom/atom-shell) binary distribution

**Port from [grunt-download-atom-shell](http://github.com/atom/grunt-download-atom-shell)**

## Forked Version Instruction

In this forked version, we check if a cached version (in os temp folder) of Atom exsited by checking 'Atom.app' instead of version file.

## Installation

Install gulp plugin package:
```sh
npm install --save-dev gulp-download-atom-shell
```

## Usage

### Options
* `version` - **Required** The version of atom-shell you want to download.
* `outputDir` - **Required** Where to put the downloaded atom-shell.
* `downloadDir` - Where to find and save cached downloaded atom-shell.
* `symbols` - Download debugging symbols instead of binaries, default to `false`.
* `rebuild` - Whether to rebuild native modules after atom-shell is downloaded.
* `apm` - The path to apm.

### Example

gulpfile.js

```javascript
var gulp = require('gulp');
var downloadatomshell = require('gulp-download-atom-shell');

gulp.task('downloadatomshell', function(cb){
	downloadatomshell({
      version: '0.12.5',
      outputDir: 'binaries'
    }, cb);
});

gulp.task('default', ['downloadatomshell']);
```
