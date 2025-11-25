import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import mathjax3 from "markdown-it-mathjax3";
import footnote from "markdown-it-footnote";
import path from 'path'

// https://vitepress.dev/reference/site-config
export default defineConfig({
    base: '/Tyler.jl/previews/PR140/',
    title: "Tyler",
    description: "Maps",
    lastUpdated: true,
    cleanUrls: true,
    outDir: '../1', // This is required for MarkdownVitepress to work correctly...
    head: [["link", { rel: "icon", href: "/public/favicon.ico" }]],
    vite: {
        resolve: {
          alias: {
            '@': path.resolve(__dirname, '../components')
          }
        },
        build: {
          assetsInlineLimit: 0, // so we can tell whether we have created inlined images or not, we don't let vite inline them
        },
        optimizeDeps: {
          exclude: [ 
            '@nolebase/vitepress-plugin-enhanced-readabilities/client',
            'vitepress',
            '@nolebase/ui',
          ], 
        }, 
        ssr: { 
          noExternal: [ 
            // If there are other packages that need to be processed by Vite, you can add them here.
            '@nolebase/vitepress-plugin-enhanced-readabilities',
            '@nolebase/ui',
          ], 
        },
      },
    markdown: {
        math: true,
        config(md) {
            md.use(tabsMarkdownPlugin), md.use(mathjax3), md.use(footnote);
        },
        theme: {
            light: "github-light",
            dark: "github-dark",
        },
    },

    themeConfig: {
        outline: "deep",
        // https://vitepress.dev/reference/default-theme-config
        logo: { src: "/logo.png", width: 24, height: 24 },
        search: {
            provider: "local",
            options: {
                detailedView: true,
            },
        },
        nav: [
            { text: "Home", link: "/" },
            { text: "Getting Started", link: "/getting_started" },
            {
                text: "Examples",
                items: [
                    { text: "Points, Poly & text", link: "/points_poly_text" },
                    { text: "OpenStreetMap data", link: "/osmmakie" },
                    { text: "Whale shark trajectory", link: "/whale_shark" },
                    { text: "Ice loss animation", link: "/iceloss_ex" },
                    {
                        text: "Interpolation On The Fly",
                        link: "/interpolation",
                    },
                    {
                        text: "Map3D",
                        link: "/map-3d",
                    },
                ],
            },

            { text: "API", link: "/api" },
        ],

        sidebar: [
            {
                text: "Getting Started",
                link: "/getting_started",
                items: [
                    { text: "Points, Poly & text", link: "/points_poly_text" },
                    { text: "OpenStreetMap data", link: "/osmmakie" },
                    { text: "Whale shark trajectory", link: "/whale_shark" },
                    { text: "Ice loss animation", link: "/iceloss_ex" },
                    {
                        text: "Interpolation On The Fly",
                        link: "/interpolation",
                    },
                    { text: "Map3D", link: "/map-3d" },

                    { text: "API", link: "/api" },
                ],
            },
        ],
        editLink: {
            pattern:
                "https://github.com/MakieOrg/Tyler.jl/edit/master/docs/src/:path",
        },
        socialLinks: [
            { icon: "github", link: "https://github.com/MakieOrg/Tyler.jl" },
        ],
        footer: {
            message:
                'Made with <a href="https://luxdl.github.io/DocumenterVitepress.jl/" target="_blank"><strong>DocumenterVitepress.jl</strong></a> <br>',
            copyright: `© Copyright ${new Date().getUTCFullYear()}. Released under the MIT License.`,
        },
    },
});
