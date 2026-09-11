# Readable greeting regression

`readable-before-pixel-match.mp4` is a 1.2-second central-text crop from the September 10 Legend shell measured run 7. It contains no title bar or other application UI. The greeting is already readable around video time 367 ms; the old downscaled pixel matcher reported content around 1050 ms. The regression ensures OCR recognizes three consecutive readable frames before that incorrect boundary.
