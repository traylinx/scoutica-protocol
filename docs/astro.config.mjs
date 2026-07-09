// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  site: 'https://docs.scoutica.com',
  integrations: [
    starlight({
      title: 'Scoutica Protocol',
      description: 'Your skills. Your rules. Your data. The open protocol for candidate-owned, AI-readable professional profiles.',
      favicon: '/images/favicon.ico',
      customCss: ['./src/styles/custom.css'],
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/traylinx/scoutica-protocol' },
      ],
      sidebar: [
    {
      label: "Get Started",
      items: [
        { slug: "introduction" },
        { slug: "quickstart" },
        { slug: "installation" },
      ],
    },
    {
      label: "CLI Reference",
      items: [
        { slug: "cli/overview" },
        { slug: "cli/init" },
        { slug: "cli/import" },
        { slug: "cli/scan" },
        { slug: "cli/validate" },
        { slug: "cli/publish" },
        { slug: "cli/preview" },
        { slug: "cli/resolve" },
        { slug: "cli/info" },
        { slug: "cli/doctor" },
        { slug: "cli/status" },
        { slug: "cli/logs" },
        { slug: "cli/update" },
      ],
    },
    {
      label: "Employer & Roles",
      items: [
        { slug: "cli/org" },
        { slug: "cli/role" },
      ],
    },
    {
      label: "Network & Messaging",
      items: [
        { slug: "cli/evaluate" },
        { slug: "cli/jobs" },
        { slug: "cli/send" },
        { slug: "cli/inbox" },
        { slug: "cli/reply" },
        { slug: "cli/deliver" },
        { slug: "cli/register" },
        { slug: "cli/identity" },
      ],
    },
    {
      label: "Your Skill Card",
      items: [
        { slug: "skill-card/overview" },
        { slug: "skill-card/profile" },
        { slug: "skill-card/rules" },
        { slug: "skill-card/evidence" },
        { slug: "skill-card/discovery" },
        { slug: "skill-card/employer" },
      ],
    },
    {
      label: "Guides",
      items: [
        { slug: "guides/create-card" },
        { slug: "guides/from-ai-job-search" },
        { slug: "guides/privacy-zones" },
        { slug: "guides/use-cases" },
        { slug: "guides/maintenance" },
        { slug: "guides/troubleshooting" },
        { slug: "guides/employers" },
      ],
    },
    {
      label: "Integration",
      items: [
        { slug: "developer/overview" },
        { slug: "developer/fetching-cards" },
        { slug: "developer/discovery-protocol" },
        { slug: "developer/evaluating-candidates" },
        { slug: "developer/evidence-verification" },
        { slug: "developer/schema-validation" },
      ],
    },
    {
      label: "Architecture",
      items: [
        { slug: "architecture/overview" },
        { slug: "architecture/six-pillars" },
        { slug: "architecture/data-model" },
        { slug: "architecture/compliance" },
      ],
    },
    {
      label: "Roadmap",
      items: [
        { slug: "roadmap" },
      ],
    },
  ],
    }),
  ],
  vite: {
    resolve: {
      alias: {
        '@components': fileURLToPath(new URL('./src/components', import.meta.url)),
      },
    },
  },
});
