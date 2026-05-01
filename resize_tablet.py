from PIL import Image

def resize_to_min_1080(input_path, output_path, target_width=1920, target_height=1080):
    img = Image.open(input_path).convert('RGB')
    width, height = img.size
    aspect_ratio = target_width / target_height
    img_ratio = width / height
    
    if img_ratio > aspect_ratio:
        new_width = int(aspect_ratio * height)
        offset = (width - new_width) / 2
        crop_box = (offset, 0, width - offset, height)
    else:
        new_height = int(width / aspect_ratio)
        offset = (height - new_height) / 2
        crop_box = (0, offset, width, height - offset)
        
    img = img.crop(crop_box)
    img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)
    img.save(output_path, "PNG")

img1 = r"C:\Users\user\.gemini\antigravity\brain\38b0efe7-1a23-497a-9b43-d1dfb2199cc6\tablet_expense_raw_1773388505268.png"
img2 = r"C:\Users\user\.gemini\antigravity\brain\38b0efe7-1a23-497a-9b43-d1dfb2199cc6\tablet_location_raw_1773388531257.png"

out1 = r"C:\Users\user\.gemini\antigravity\brain\38b0efe7-1a23-497a-9b43-d1dfb2199cc6\tablet_screenshot_1.png"
out2 = r"C:\Users\user\.gemini\antigravity\brain\38b0efe7-1a23-497a-9b43-d1dfb2199cc6\tablet_screenshot_2.png"

resize_to_min_1080(img1, out1)
resize_to_min_1080(img2, out2)

print("Tablet screenshots resized to 1920x1080 successfully")
