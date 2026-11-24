import { Agents } from "@/components/site/agents";
import { Claude } from "@/components/site/claude";
import { Customize } from "@/components/site/customize";
import { Faq } from "@/components/site/faq";
import { Features } from "@/components/site/features";
import { Footer } from "@/components/site/footer";
import { Hero } from "@/components/site/hero";
import { Install } from "@/components/site/install";
import { Nav } from "@/components/site/nav";

export default function Home() {
  return (
    <>
      <Nav />
      <main className="flex-1">
        <Hero />
        <Claude />
        <Features />
        <Agents />
        <Customize />
        <Install />
        <Faq />
      </main>
      <Footer />
    </>
  );
}
