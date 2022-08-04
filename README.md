[![CI](https://github.com/machshev/haqor/actions/workflows/ci.yml/badge.svg)](https://github.com/machshev/haqor/actions/workflows/ci.yml)

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Haqor Bible study App](#haqor-bible-study-app)
- [Why the name Haqor?](#why-the-name-haqor)
- [Why yet another bible application?](#why-yet-another-bible-application)
    - [Original language study](#original-language-study)
    - [First class original language study](#first-class-original-language-study)
    - [All features on any device](#all-features-on-any-device)
    - [Cost for good quality original language study tools](#cost-for-good-quality-original-language-study-tools)
    - [Aramaic - Peshitta](#aramaic---peshitta)

<!-- markdown-toc end -->


# Haqor Bible study App

Original language study first Bible software that can be used on all devices - mobile, tablet, and
desktop.

# Why the name Haqor?

The name is taken from the word חֲקֹר ("search out") from proverbs 25, where it says:

  > It is the glory of Elohim to conceal a thing: but the honour of kings is to search out a
  > matter. (**Prov 25:2**)

This software is for people who are searching out the word of Yahweh for themselves. I am Christian
(Christadelphian) and like to spend time studying the bible in it's original languages.

# Why yet another bible application?

Haqor is in very early stages of development. So the following is to explain the vision in more
detail and provide a bit of a road-map of sorts.

## Original language study

There are many bible applications that are English language reading first bible applications and
focused on reading the bible via the many and varied English translations. The problem is that every
translation from one language to another is inevitably part interpretation as one language is not
directly equivalent to another.

Often these interpretations are okay and don't really impact the overall meaning. Other times depth
of meaning is lost or hidden, or even adds theological meaning that is not justified from the
original. For example choosing to transliterate (copy over the sounds of the original words)
"Devil" and "Satan", turning them into proper names and attaching new meaning to these new
words. Instead of translating (copy over the meaning using equivalent words) with phrases/words such
as "false accuser" and "adversary".

These are theological choices and not intrinsic to the original Hebrew/Greek/Aramaic
words. Personally I think these interpretation choices should be more transparent, which is
probably one of the biggest benefits of studying in the original languages directly. My hope is
that this software makes it easier to study the bible in it's original languages.

## First class original language study

Most bible software currently existing is designed primarily for reading the bible in the English
language. They often provide some bolt on tools to access the original languages, but they feel to
me more of a secondary consideration with poor integration. There is less software out there right
now (as I write this), aimed primarily at reading and studying the original language and works well
with my personal study style.

Often the original language resources are treated as just another "bible version" or "resource" on a
different window. You can link those windows and sometimes get them to scroll together to some
degree or another, however they are generally treated as separate entities. Logos for example allows
you to link windows by adding them to groups. But that's a lot of manual effort when I want to open
up five different passages, some in the *Old Testament* (OT) and others in the *New Testament* (NT)
and also have access to their corresponding original language texts. That requires manual linking
of 10 different windows to achieve something close to usable.

Haqor aims to make bible views that have seamless navigation between different passages in both
English and the original languages.

Another issue with existing bible software is that I've not yet come across one that will
automatically switch from Hebrew, to Greek or Aramaic if you go from the OT to the NT. So you could
follow a cross reference or want to jump from OT to NT and the linked original language window will
either go blank (as there is no text in resource for that verse) or remain in the previous OT
passage breaking the "link". It would be really nice if you didn't have to manually switch resource
or have both Hebrew and Greek resources "linked" in three open windows to get a "smooth" transition
between OT and NT passages.

Haqor should know what language is required given the verse location (OT or NT) and automatically
switch.

## All features on any device

At the moment I use a mix of resources because there isn't one single tool that does
everything. There are already lots of resources available, from physical books, websites, mobile
(android) apps like and-bible or logos, up to full desktop applications like bibletime and logos
bible software. All of these resources are invaluable, but one integrated solution across all devices
would be far better.

There isn't currently a bible tool that can work on desktop and mobile, with all the features
available on all platforms. There are good mobile solutions and good desktop solutions, but nothing
that does both mobile and Desktop. I use Android, but some of my friends use apple devices... and I
find I can't recommend the apps I use as they are not available on apple devices. With modern mobile
devices, there is more than enough processing power to support desktop features on a mobile
device. The only difference should be that the mobile has a smaller screen.

Logos bible study software is currently the closes thing I've seen to achieving this. However it's
clear they are building on legacy code bases and have a mobile version that is significantly
different to the desktop version in terms of features.

Haqor should be a single code base usable across all devices - mobile, tablet, desktop, and
potentially even a web based version. Until recently there wasn't really a solution that could
deliver on this, but now there is [flutter](https://flutter.dev/).

## Cost for good quality original language study tools

I strongly believe that access to basic study tools should be completely free. Everyone should have
free access to the text of the bible in all the original languages. It should be possible to access
all the public domain lexicons and glossaries without having to pay to use them in one particular
bible software tool.

Long gone are the days when we needed hand crafted concordances, and therefore reasonable payment
for the effort of those who spent many years of their lives curating these works e.g. the
concordance part of strongs (excluding the glosses) and englishman's. It's trivial to write software
to index and search bible texts now.

Companies like Logos have good searching capabilities, but charge fairly high costs for the
privilege. While other free solutions don't quite meet the standard of these paid solutions. Haqor
aims to provide high quality searching of bible for free.

Just to be clear, I'm a customer of Logos and have spent a lot of money on their resources. Under
the law of Moses, the Levites were paid to spend their time studying and teaching the
people. Something they couldn't do without that financial support. Logos provide many resources that
have resulted from the life work of many people, and I've no problem at all with them receiving
financial support for this effort. Logos also support a number of software developers with a salary,
so that the tool can exist, and they have reasonably chosen to charge for some of the software
features I personally think should be freely available... but that is their choice to make. I'm
intending to provide an alternative for the basic study features using what is freely available in
the pubic domain.

Where Logos excels is the vast number of resources, lexicons, grammars, commentaries, bible atlases,
apologetics works, and numerous books. All searchable and integrated with the the bible study
software. Haqor is not intending to even attempt to replace this, even if it were possible. At some
point it would be nice if Haqor would integrate with Logos in such a way that you could open a logos
resource search, or access one of the many paid for Lexicons (like DCH) in the logos bible software
by clicking a link in Haqor. Both working alongside each other complimenting each other.

## Aramaic - Peshitta

While opinions differ about how much significance to place on the Peshitta. Ranging from just
another early translation, to the belief that Jesus spoke Aramaic and that all or at least some of
the NT was originally given in Aramaic. Personally I'm currently of the opinion that Jesus used
Galilean Aramaic in his ministry and that at least some of the NT was likely originally recorded in
Aramaic (Syriac?) in Antioch, and translated to Greek.

The implications of this are significant, as if true, would mean both OT and NT were written in a
Semitic language and so word links back to the OT would be significantly easier using the shared
Semitic root words. Word links within the Hebrew text itself are one of the many reasons I am
confident the bible is not a man made fabrication. It fits together far too well for that, in my
view. I'd like to be able to study the Aramaic Peshitta with the same ease that I can with the
Hebrew. If nothing more than as an experiment tool to see how well it fits with the OT Hebrew and
help highlight any major differences between Peshitta and the Greek.

Support for the Peshitta in existing tools is not very good. There are some paid bible software
modules available, but these are based on resources that have been in the public domain for many
years and in my view should not be charged for. There is a really powerful website
[Dukhrana](https://www.dukhrana.com/peshitta/index.php) which provides the best bible study support
I've found for the Peshitta, but it's web based and therefore not available online.

Another issue is that the Peshitta is written in Syriac Aramaic, which has several alphabets. I'm
not familiar enough to be able to read those alphabets... but it's trivial to transliterate it into
Hebrew alphabet with no loss of meaning. This also means it's easier to see the shared Semitic root
of OT Hebrew words.

Haqor should provide the Peshitta text and allow changing the font, including to a Hebrew font.

## Using Rust Inside Flutter

This project leverages Flutter for GUI and Rust for the backend logic,
utilizing the capabilities of the
[Rinf](https://pub.dev/packages/rinf) framework.

To run and build this app, you need to have
[Flutter SDK](https://docs.flutter.dev/get-started/install)
and [Rust toolchain](https://www.rust-lang.org/tools/install)
installed on your system.
You can check that your system is ready with the commands below.
Note that all the Flutter subcomponents should be installed.

```shell
rustc --version
flutter doctor
```

You also need to have the CLI tool for Rinf ready.

```shell
cargo install rinf_cli
```

Signals sent between Dart and Rust are implemented using signal attributes.
If you've modified the signal structs, run the following command
to generate the corresponding Dart classes:

```shell
rinf gen
```

Now you can run and build this app just like any other Flutter projects.

```shell
flutter run
```

For detailed instructions on writing Rust and Flutter together,
please refer to Rinf's [documentation](https://rinf.cunarist.com).
