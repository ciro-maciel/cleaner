#!/usr/bin/env node
// Writes docs/RULES.md and docs/pt-BR/RULES.md from rules.json: every rule Cleaner cleans by,
// readable without opening the code. Run it after changing rules.json:
//
//   node scripts/rules-doc.mjs
//
// The idea of a readable directory of every rule comes from Kudu (https://github.com/AdventDevInc/kudu).
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'

const { rules } = JSON.parse(readFileSync('rules.json', 'utf8'))
const code = list => (list?.length ? list.map(item => `\`${item}\``).join(', ') : '—')

const LANG = {
  en: {
    file: 'docs/RULES.md',
    title: 'Every rule Cleaner cleans by',
    intro: `Cleaner only looks where a rule in [\`rules.json\`](../rules.json) tells it to. These are all ${rules.length} of them, written from that file by \`scripts/rules-doc.mjs\`. Whatever you remove waits 7 days in the quarantine first.`,
    mode: { children: 'each item inside the folder', files: 'files inside the folder', self: 'the folder itself' },
    risk: { low: 'low', medium: 'medium' },
    rows: ['Why it is safe', 'Where', 'What is removed', 'Left out', 'Only these extensions', 'Only older than', 'Risk', 'On by default'],
    yes: 'yes', no: 'no, you choose it', days: n => `${n} days`, skip: 'Skips apps that are running',
    name: rule => rule.titleEn ?? rule.title, why: rule => rule.whyEn ?? rule.why,
  },
  pt: {
    file: 'docs/pt-BR/RULES.md',
    title: 'Todas as regras com que o Cleaner limpa',
    intro: `O Cleaner só olha onde uma regra do [\`rules.json\`](../../rules.json) manda. Estas são as ${rules.length}, escritas a partir desse arquivo pelo \`scripts/rules-doc.mjs\`. O que você remove passa 7 dias na quarentena antes.`,
    mode: { children: 'cada item dentro da pasta', files: 'os arquivos dentro da pasta', self: 'a própria pasta' },
    risk: { low: 'baixo', medium: 'médio' },
    rows: ['Por que é seguro', 'Onde', 'O que sai', 'Fica de fora', 'Só estas extensões', 'Só mais antigos que', 'Risco', 'Ligada por padrão'],
    yes: 'sim', no: 'não, você escolhe', days: n => `${n} dias`, skip: 'Pula os apps que estão abertos',
    name: rule => rule.title, why: rule => rule.why,
  },
}

for (const t of Object.values(LANG)) {
  const out = [`# ${t.title}`, '', t.intro, '']
  for (const rule of rules) {
    out.push(`## ${t.name(rule)} \`${rule.id}\``, '', `| | |`, `| --- | --- |`)
    out.push(`| ${t.rows[0]} | ${t.why(rule)} |`)
    out.push(`| ${t.rows[1]} | ${code(rule.paths)} |`)
    out.push(`| ${t.rows[2]} | ${t.mode[rule.mode]} |`)
    if (rule.exclude?.length) out.push(`| ${t.rows[3]} | ${code(rule.exclude)} |`)
    if (rule.extensions?.length) out.push(`| ${t.rows[4]} | ${code(rule.extensions)} |`)
    if (rule.minAgeDays) out.push(`| ${t.rows[5]} | ${t.days(rule.minAgeDays)} |`)
    out.push(`| ${t.rows[6]} | ${t.risk[rule.risk]}${rule.skipRunningApps ? ` · ${t.skip}` : ''} |`)
    out.push(`| ${t.rows[7]} | ${rule.defaultOn ? t.yes : t.no} |`, '')
  }
  mkdirSync(t.file.slice(0, t.file.lastIndexOf('/')), { recursive: true })
  writeFileSync(t.file, out.join('\n'))
  console.log(`${t.file}: ${rules.length} rules`)
}
