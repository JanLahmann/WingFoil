import sys, hashlib, glob, os
from PIL import Image
d = sys.argv[1]; out = sys.argv[2]
files = sorted(glob.glob(os.path.join(d, "cap-*.png")))
uniq, seen = [], set()
for f in files:
    h = hashlib.md5(open(f, "rb").read()).hexdigest()
    if h in seen: continue
    seen.add(h); uniq.append(f)
print(len(files), "captures,", len(uniq), "unique")
ims = [Image.open(f) for f in uniq]
w = max(i.width for i in ims); h = max(i.height for i in ims)
cols = 6; rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * h), "white")
for k, im in enumerate(ims):
    sheet.paste(im, ((k % cols) * w, (k // cols) * h))
sheet.save(out); print("wrote", out, sheet.size, [os.path.basename(f) for f in uniq])
