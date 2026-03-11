import PyPDF2

try:
    with open('c:/Users/user/benzdesk/benzmobitraq_mobile/Travel policy.pdf', 'rb') as file:
        reader = PyPDF2.PdfReader(file)
        text = ''
        for page in reader.pages:
            text += page.extract_text() + '\n'
        with open('parse_pdf.txt', 'w', encoding='utf-8') as out:
            out.write(text)
except Exception as e:
    import pypdf
    with open('c:/Users/user/benzdesk/benzmobitraq_mobile/Travel policy.pdf', 'rb') as file:
        reader = pypdf.PdfReader(file)
        text = ''
        for page in reader.pages:
            text += page.extract_text() + '\n'
        with open('parse_pdf.txt', 'w', encoding='utf-8') as out:
            out.write(text)
