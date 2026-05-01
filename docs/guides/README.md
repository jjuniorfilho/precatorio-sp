# 📚 Guias Detalhados Cortex v2.0

Guias práticos e aprofundados para funcionalidades específicas do Cortex Framework.

---

## 📖 Guias Disponíveis

### 🔍 Sistema de Discovery

**[discover-workflow.md](./discover-workflow.md)** - Guia completo do comando `/discover`
- Quando e por que usar
- Estrutura do briefing gerado
- Carregamento seletivo de contexto
- Integração com `/start`, `/plan` e `/work`
- Troubleshooting

### 🎯 Abordagem Proativa com ADRs

**[adr-proactive-approach.md](./adr-proactive-approach.md)** - Filosofia e prática
- Mudança de paradigma: Reativo → Proativo
- Como consultar ADRs ANTES de implementar
- Validação de sanidade vs correção de erros
- Exemplos práticos
- Métricas de sucesso

### 🔄 Integração Lovable-Backend

**[lovable-integration.md](./lovable-integration.md)** - Mapeamento e integração
- Como o `@lovable-backend-mapper` funciona
- Padrões de mock detectados
- Geração de checklists de integração
- Mock Removal workflow
- Validação de tipos frontend ↔ backend

### 🐛 Investigação Forense de Bugs

**[bug-collect-workflow.md](./bug-collect-workflow.md)** - Guia do comando `/bug-collect`
- Diferença entre `/collect` e `/bug-collect`
- 6 fases da investigação forense
- Regras de segurança para queries em produção
- Template de issue com root-cause analysis
- Integração com Linear e GitHub Issues

### 📊 Migração v1.x → v2.0

**[migration-guide.md](./migration-guide.md)** - Guia de migração
- Breaking changes
- Migração de estrutura de pastas
- Adaptação de workflows existentes
- Atualização de comandos customizados
- Checklist de migração

---

## 🎓 Como Usar Estes Guias

1. **Para Aprender**: Leia os guias na ordem sugerida acima
2. **Para Referência**: Use como consulta rápida durante desenvolvimento
3. **Para Troubleshooting**: Consulte seções específicas quando encontrar problemas

---

## 📝 Status dos Guias

| Guia | Status | Última Atualização |
|------|--------|-------------------|
| discover-workflow.md | ✅ Disponível | 2025-01-26 |
| adr-proactive-approach.md | ✅ Disponível | 2025-01-26 |
| bug-collect-workflow.md | ✅ Disponível | 2026-02-22 |
| lovable-integration.md | 📝 Em breve | - |
| migration-guide.md | 📝 Em breve | - |

---

## 🤝 Contribuindo

Encontrou algo confuso ou que poderia ser melhorado? Contribuições são bem-vindas!

1. Identifique o guia que precisa de atualização
2. Crie issue ou PR com sugestões
3. Siga o template de guia existente

---

**Versão do Framework**: 2.4.0
**Última Atualização**: 2026-02-22
