from PIL import Image, ImageEnhance

def create_feature_graphic(bg_path, logo_path, output_path, target_width=1024, target_height=500):
    # 1. Open background and logo
    bg = Image.open(bg_path).convert('RGBA')
    logo = Image.open(logo_path).convert('RGBA')
    
    # 2. Crop to aspect ratio and resize background
    width, height = bg.size
    aspect_ratio = target_width / target_height
    img_ratio = width / height
    
    if img_ratio > aspect_ratio:
        # Image is wider than target ratio
        new_width = int(aspect_ratio * height)
        offset = (width - new_width) / 2
        crop_box = (offset, 0, width - offset, height)
    else:
        # Image is taller than target ratio
        new_height = int(width / aspect_ratio)
        offset = (height - new_height) / 2
        crop_box = (0, offset, width, height - offset)
        
    bg = bg.crop(crop_box)
    bg = bg.resize((target_width, target_height), Image.Resampling.LANCZOS)
    
    # Make logo bigger and center it
    logo_target_width = 400
    logo_ratio = logo.size[1] / logo.size[0]
    logo_target_height = int(logo_target_width * logo_ratio)
    
    logo = logo.resize((logo_target_width, logo_target_height), Image.Resampling.LANCZOS)
    
    # Paste logo in the center
    x = (target_width - logo_target_width) // 2
    y = (target_height - logo_target_height) // 2
    
    bg.paste(logo, (x, y), logo)
    
    # Save as PNG
    bg.convert('RGB').save(output_path, "PNG")

if __name__ == "__main__":
    bg_path = r"C:\Users\user\.gemini\antigravity\brain\38b0efe7-1a23-497a-9b43-d1dfb2199cc6\feature_graphic_raw_2_1773387687247.png"
    logo_path = r"c:\Users\user\benzdesk\logo.png"
    output_path = r"C:\Users\user\.gemini\antigravity\brain\38b0efe7-1a23-497a-9b43-d1dfb2199cc6\feature_graphic.png"
    create_feature_graphic(bg_path, logo_path, output_path)
    print("Feature graphic created successfully")
