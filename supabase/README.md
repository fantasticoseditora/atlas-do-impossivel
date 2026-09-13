# Backend do Mural

Arquitetura de referência: Supabase Free + Cloudflare Turnstile Free. Não há credenciais neste repositório.

## Variáveis secretas da Edge Function

SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, TURNSTILE_SECRET, HASH_SECRET, SITE_ORIGIN e SITE_HOSTNAME.

A chave service_role e os segredos nunca entram no frontend. O endpoint só aceita a origem configurada, exige usuário com e-mail confirmado, valida Turnstile no servidor, aplica limite atômico e chama função SQL disponível apenas ao papel service_role.

## Ordem de implantação

1. Confirmar que o projeto gratuito não solicita cartão nem habilita billing.
2. Aplicar migrations/001_init.sql.
3. Inserir metadados públicos da edição e os UUIDs dos portais.
4. Criar o widget Turnstile.
5. Configurar os segredos.
6. Publicar cast-vote.
7. Rodar testes com as chaves oficiais de teste do Turnstile.
8. Só então habilitar public_status=open.
