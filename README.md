# AlpineLinuxChannel

Scripts used for managing an Alpine Linux repository

Scripts:

- rooter: keep `sudo` permissions
- aports: download aports sources
- arm: Manage Alpine Linux chroots for clean builds
- builder: Manage the build process
- common.php : Update scripts to make sure that common code is kept
  updated
- common.sh : Code that is shared by all scripts.
- seed.sh : Keep APORTs code maintained

The main driver script is `mk`.  You only need to do `mk world`.

## TODO

* arm
  - list chroots

* * *

# NOTES

Look in:

http://git.alpinelinux.org/cgit/aports/tree/

.travis stuff
scripts


Scripts:

- [x] seed : Initialize source repository (NOT NEEDED)
- [ ] builder : Build packages
- [x] rooter : manage `sudo` permissions


  # List chroots
