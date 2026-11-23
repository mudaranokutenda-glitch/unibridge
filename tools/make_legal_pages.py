#!/usr/bin/env python3
"""Builds web/privacy.html and web/delete-account.html from lib/legal.dart.

The text lives in ONE place: lib/legal.dart (shown inside the app).
After changing it, run from the project folder:
    python tools/make_legal_pages.py
The pages are published with the web version (GitHub Pages):
    https://mudaranokutenda-glitch.github.io/unibridge/privacy.html
    https://mudaranokutenda-glitch.github.io/unibridge/delete-account.html
"""
import html
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = open(os.path.join(ROOT, 'lib', 'legal.dart'), encoding='utf-8').read()


def const(name):
    m = re.search(r"const String %s = '([^']*)';" % name, SRC)
    return m.group(1)


CONSTS = {k: const(k) for k in ('kContactEmail', 'kLegalLastUpdatedEn', 'kLegalLastUpdatedFr')}


def read_literal(s, i):
    """Reads one Dart string literal starting at s[i] (a quote). Returns (text, next index)."""
    q = s[i]
    i += 1
    out = []
    while s[i] != q:
        c = s[i]
        if c == '\\':
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t'}.get(n, n))
            i += 2
            continue
        if c == '$':
            m = re.match(r'\$([A-Za-z_]\w*)', s[i:])
            out.append(CONSTS[m.group(1)])
            i += len(m.group(0))
            continue
        out.append(c)
        i += 1
    return ''.join(out), i + 1


def sections(list_name):
    """The (title, text) pairs of a `const List<LegalSection> NAME = [...]`."""
    start = SRC.index('const List<LegalSection> %s = [' % list_name)
    i = SRC.index('[', start) + 1
    result, fields, current, depth = [], [], [], 0
    while True:
        c = SRC[i]
        if SRC.startswith('//', i):
            i = SRC.index('\n', i)
            continue
        if c in '\'"':
            text, i = read_literal(SRC, i)
            current.append(text)
            continue
        if c == '(':
            depth += 1
            fields, current = [], []
        elif c == ',' and depth == 1:
            fields.append(''.join(current))
            current = []
        elif c == ')':
            depth -= 1
            if current:
                fields.append(''.join(current))
            result.append((fields[0], fields[1]))
            current = []
        elif c == ']' and depth == 0:
            return result
        i += 1


def to_html(text):
    """Plain text -> HTML: lines starting with • become a list; 'Label:' is bold."""
    email = CONSTS['kContactEmail']
    parts, items = [], []

    def flush():
        if items:
            parts.append('<ul>' + ''.join('<li>%s</li>' % x for x in items) + '</ul>')
            items.clear()

    for line in text.split('\n'):
        line = line.strip()
        if not line:
            continue
        esc = html.escape(line)
        esc = esc.replace(html.escape(email), '<a href="mailto:%s">%s</a>' % (email, email))
        if line.startswith('•'):
            body = esc.lstrip('•').strip()
            m = re.match(r'([^:]{1,60}?)(\s?:)(\s.*)', body)
            items.append('<b>%s%s</b>%s' % (m.group(1), m.group(2), m.group(3)) if m else body)
        else:
            flush()
            parts.append('<p>%s</p>' % esc)
    flush()
    return '\n'.join(parts)


STYLE = """
  :root { --bg:#ffffff; --text:#14233B; --muted:#5b6b7b; --accent:#2F80ED; --line:#dbe4f0; --card:#f4f8fd; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#0f1621; --text:#e6edf6; --muted:#9fb0c4; --accent:#6aa8ff; --line:#2a3646; --card:#172231; }
  }
  body { margin:0; background:var(--bg); color:var(--text);
         font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }
  main { max-width:760px; margin:0 auto; padding:20px 16px 56px; }
  header { display:flex; align-items:center; gap:12px; }
  header img { width:56px; height:56px; }
  .brand { font:900 30px Georgia,"Times New Roman",serif; letter-spacing:2px;
           text-shadow:2px 3px 4px rgba(0,0,0,.25); }
  h1 { color:var(--accent); margin:18px 0 2px; font-size:1.6rem; }
  h2 { margin-top:28px; font-size:1.15rem; }
  .muted { color:var(--muted); font-size:.92rem; }
  nav { margin:14px 0; }
  nav a { margin-right:14px; }
  a { color:var(--accent); }
  .card { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:4px 18px; margin:18px 0; }
  hr { border:0; border-top:1px solid var(--line); margin:48px 0; }
  ol li, ul li { margin:4px 0; }
"""


def page(title, body):
    return """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<link rel="icon" type="image/png" href="favicon.png">
<style>%s</style>
</head>
<body>
<main>
<header><img src="icons/Icon-192.png" alt=""><span class="brand">AZSA</span></header>
<!-- Made by tools/make_legal_pages.py from lib/legal.dart: do not edit by hand. -->
%s
</main>
</body>
</html>
""" % (html.escape(title), STYLE, body)


def render_sections(secs, delete_id):
    out = []
    for title, text in secs:
        is_delete = title in ('Deleting your account', 'Supprimer votre compte')
        anchor = ' id="%s"' % delete_id if is_delete else ''
        out.append('<h2%s>%s</h2>\n%s' % (anchor, html.escape(title), to_html(text)))
    return '\n'.join(out)


def privacy_page():
    en_p, en_t = sections('kPrivacyEn'), sections('kTermsEn')
    fr_p, fr_t = sections('kPrivacyFr'), sections('kTermsFr')
    body = """
<nav><a href="#en">English</a><a href="#fr">Français</a><a href="delete-account.html">Delete my account</a></nav>
<section id="en" lang="en">
<h1>Privacy policy</h1>
<p class="muted">Last updated: %(upd_en)s</p>
%(en_p)s
<h1 id="terms">Terms of use</h1>
%(en_t)s
</section>
<hr>
<section id="fr" lang="fr">
<h1>Politique de confidentialité</h1>
<p class="muted">Dernière mise à jour : %(upd_fr)s</p>
%(fr_p)s
<h1 id="conditions">Conditions d'utilisation</h1>
%(fr_t)s
</section>
""" % dict(upd_en=CONSTS['kLegalLastUpdatedEn'], upd_fr=CONSTS['kLegalLastUpdatedFr'],
           en_p=render_sections(en_p, 'delete-account'), en_t=render_sections(en_t, 'x'),
           fr_p=render_sections(fr_p, 'supprimer-compte'), fr_t=render_sections(fr_t, 'x'))
    return page('AZSA - Privacy policy and terms', body)


def delete_page():
    def find(secs, title):
        return next(t for k, t in secs if k == title)
    en = find(sections('kPrivacyEn'), 'Deleting your account')
    fr = find(sections('kPrivacyFr'), 'Supprimer votre compte')
    email = CONSTS['kContactEmail']
    body = """
<nav><a href="#en">English</a><a href="#fr">Français</a><a href="privacy.html">Privacy policy</a></nav>
<section id="en" lang="en">
<h1>Delete your AZSA account</h1>
<div class="card">
<p><b>In the app</b></p>
<ol>
<li>Open AZSA and go to the <b>Profile</b> tab.</li>
<li>Tap the <b>⚙ Settings</b> gear at the top.</li>
<li>Tap <b>Delete my account</b> and type <b>DELETE</b> to confirm.</li>
</ol>
<p><b>Without the app</b>: email <a href="mailto:%(email)s?subject=Delete%%20my%%20account">%(email)s</a>
from the email address of your account, with the subject <i>Delete my account</i>.
We delete the account within 30 days.</p>
</div>
<h2>What is deleted and what is kept</h2>
%(en)s
</section>
<hr>
<section id="fr" lang="fr">
<h1>Supprimer votre compte AZSA</h1>
<div class="card">
<p><b>Dans l'application</b></p>
<ol>
<li>Ouvrez AZSA et allez dans l'onglet <b>Profil</b>.</li>
<li>Touchez la roue <b>⚙ Paramètres</b> en haut.</li>
<li>Touchez <b>Supprimer mon compte</b> et tapez <b>DELETE</b> pour confirmer.</li>
</ol>
<p><b>Sans l'application</b> : écrivez à <a href="mailto:%(email)s?subject=Supprimer%%20mon%%20compte">%(email)s</a>
depuis l'adresse e-mail de votre compte, avec le sujet <i>Supprimer mon compte</i>.
Nous supprimons le compte sous 30 jours.</p>
</div>
<h2>Ce qui est supprimé et ce qui est gardé</h2>
%(fr)s
</section>
""" % dict(email=email, en=to_html(en), fr=to_html(fr))
    return page('AZSA - Delete your account', body)


if __name__ == '__main__':
    for name, content in (('privacy.html', privacy_page()), ('delete-account.html', delete_page())):
        path = os.path.join(ROOT, 'web', name)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(content)
        print('written', os.path.relpath(path, ROOT))
