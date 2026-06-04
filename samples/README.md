# samples/

Ad-hoc test images for `start.py` — drop overhead plate photos here and run:

```bash
python start.py samples/your-meal.jpg 26
```

The second argument is the plate diameter in cm (default 26 = 10-in dinner plate).
Use a tape measure on your actual plate for accurate grams — wrong diameter
means proportionally wrong grams.

This folder is gitignored. For images that should be checked in (the eval
set used in the README accuracy table, demo video stills, etc.), put them
under `eval/images/` instead.
