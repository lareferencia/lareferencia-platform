---
description: Build the project or individual modules
---

To build the entire project, run the build script from the root directory with the target profile.

For La Referencia:
```bash
bash build.sh lareferencia
```

For IBICT:
```bash
bash build.sh ibict
```

To build a specific module, you can run the same command from within that module's directory, provided you haven't made changes to other modules that it depends on.
