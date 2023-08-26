# This shell script emits a C file. -*- C -*-
# It does some substitutions.
fragment <<EOF
/* This file is is generated by a shell script.  DO NOT EDIT! */

/* Emulate the original gld for the given ${EMULATION_NAME}
   Copyright (C) 2014-2023 Free Software Foundation, Inc.
   Written by Steve Chamberlain steve@cygnus.com
   Extended for the MSP430 by Nick Clifton  nickc@redhat.com

   This file is part of the GNU Binutils.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street - Fifth Floor, Boston,
   MA 02110-1301, USA.  */

#define TARGET_IS_${EMULATION_NAME}

#include "sysdep.h"
#include "bfd.h"
#include "bfdlink.h"
#include "ctf-api.h"

#include "ld.h"
#include "getopt.h"
#include "ldmain.h"
#include "ldmisc.h"
#include "ldexp.h"
#include "ldlang.h"
#include "ldfile.h"
#include "ldemul.h"
#include "libiberty.h"
#include <ldgram.h>

enum regions
{
  REGION_NONE = 0,
  REGION_LOWER,
  REGION_UPPER,
  REGION_EITHER = 3,
};

enum either_placement_stage
{
  LOWER_TO_UPPER,
  UPPER_TO_LOWER,
};

enum { ROM, RAM };

static int data_region = REGION_NONE;
static int code_region = REGION_NONE;
static bool disable_sec_transformation = false;

#define MAX_PREFIX_LENGTH 7

EOF

# Import any needed special functions and/or overrides.
#
if test -n "$EXTRA_EM_FILE" ; then
  source_em ${srcdir}/emultempl/${EXTRA_EM_FILE}.em
fi

if test x"$LDEMUL_BEFORE_PARSE" != xgld"$EMULATION_NAME"_before_parse; then
fragment <<EOF

static void
gld${EMULATION_NAME}_before_parse (void)
{
#ifndef TARGET_			/* I.e., if not generic.  */
  ldfile_set_output_arch ("`echo ${ARCH}`", bfd_arch_unknown);
#endif /* not TARGET_ */

  /* The MSP430 port *needs* linker relaxtion in order to cope with large
     functions where conditional branches do not fit into a +/- 1024 byte range.  */
  if (!bfd_link_relocatable (&link_info))
    TARGET_ENABLE_RELAXATION;
}

EOF
fi

if test x"$LDEMUL_GET_SCRIPT" != xgld"$EMULATION_NAME"_get_script; then
fragment <<EOF

static char *
gld${EMULATION_NAME}_get_script (int *isfile)
EOF

if test x"$COMPILE_IN" = xyes
then
# Scripts compiled in.

# sed commands to quote an ld script as a C string.
sc="-f ${srcdir}/emultempl/stringify.sed"

fragment <<EOF
{
  *isfile = 0;

  if (bfd_link_relocatable (&link_info) && config.build_constructors)
    return
EOF
sed $sc ldscripts/${EMULATION_NAME}.xu                 >> e${EMULATION_NAME}.c
echo '  ; else if (bfd_link_relocatable (&link_info)) return' >> e${EMULATION_NAME}.c
sed $sc ldscripts/${EMULATION_NAME}.xr                 >> e${EMULATION_NAME}.c
echo '  ; else if (!config.text_read_only) return'     >> e${EMULATION_NAME}.c
sed $sc ldscripts/${EMULATION_NAME}.xbn                >> e${EMULATION_NAME}.c
echo '  ; else if (!config.magic_demand_paged) return' >> e${EMULATION_NAME}.c
sed $sc ldscripts/${EMULATION_NAME}.xn                 >> e${EMULATION_NAME}.c
echo '  ; else return'                                 >> e${EMULATION_NAME}.c
sed $sc ldscripts/${EMULATION_NAME}.x                  >> e${EMULATION_NAME}.c
echo '; }'                                             >> e${EMULATION_NAME}.c

else
# Scripts read from the filesystem.

fragment <<EOF
{
  *isfile = 1;

  if (bfd_link_relocatable (&link_info) && config.build_constructors)
    return "ldscripts/${EMULATION_NAME}.xu";
  else if (bfd_link_relocatable (&link_info))
    return "ldscripts/${EMULATION_NAME}.xr";
  else if (!config.text_read_only)
    return "ldscripts/${EMULATION_NAME}.xbn";
  else if (!config.magic_demand_paged)
    return "ldscripts/${EMULATION_NAME}.xn";
  else
    return "ldscripts/${EMULATION_NAME}.x";
}
EOF
fi
fi

if test x"$LDEMUL_PLACE_ORPHAN" != xgld"$EMULATION_NAME"_place_orphan; then
fragment <<EOF

static unsigned int
data_statement_size (lang_data_statement_type *d)
{
  unsigned int size = 0;
  switch (d->type)
    {
    case QUAD:
    case SQUAD:
      size = QUAD_SIZE;
      break;
    case LONG:
      size = LONG_SIZE;
      break;
    case SHORT:
      size = SHORT_SIZE;
      break;
    case BYTE:
      size = BYTE_SIZE;
      break;
    default:
      einfo (_("%P: error: unhandled data_statement size\n"));
      FAIL ();
    }
  return size;
}

/* Helper function for place_orphan that computes the size
   of sections already mapped to the given statement.  */

static bfd_size_type
scan_children (lang_statement_union_type * l)
{
  bfd_size_type amount = 0;

  while (l != NULL)
    {
      switch (l->header.type)
	{
	case lang_input_section_enum:
	  if (l->input_section.section->flags & SEC_ALLOC)
	    amount += l->input_section.section->size;
	  break;

	case lang_constructors_statement_enum:
	case lang_assignment_statement_enum:
	case lang_padding_statement_enum:
	  break;

	case lang_wild_statement_enum:
	  amount += scan_children (l->wild_statement.children.head);
	  break;

	case lang_data_statement_enum:
	  amount += data_statement_size (&l->data_statement);
	  break;

	default:
	  fprintf (stderr, "msp430 orphan placer: unhandled lang type %d\n", l->header.type);
	  break;
	}

      l = l->header.next;
    }

  return amount;
}

#define WARN_UPPER 0
#define WARN_LOWER 1
#define WARN_TEXT 0
#define WARN_DATA 1
#define WARN_BSS 2
#define WARN_RODATA 3

/* Warn only once per output section.
 * NAME starts with ".upper." or ".lower.".  */
static void
warn_no_output_section (const char *name)
{
  static bool warned[2][4] = {{false, false, false, false},
			      {false, false, false, false}};
  int i = WARN_LOWER;

  if (strncmp (name, ".upper.", 7) == 0)
    i = WARN_UPPER;

  if (!warned[i][WARN_TEXT] && strcmp (name + 6, ".text") == 0)
    warned[i][WARN_TEXT] = true;
  else if (!warned[i][WARN_DATA] && strcmp (name + 6, ".data") == 0)
    warned[i][WARN_DATA] = true;
  else if (!warned[i][WARN_BSS] && strcmp (name + 6, ".bss") == 0)
    warned[i][WARN_BSS] = true;
  else if (!warned[i][WARN_RODATA] && strcmp (name + 6, ".rodata") == 0)
    warned[i][WARN_RODATA] = true;
  else
    return;
  einfo ("%P: warning: no input section rule matches %s in linker script\n",
	 name);
}


/* Place an orphan section.  We use this to put .either sections
   into either their lower or their upper equivalents.  */

static lang_output_section_statement_type *
gld${EMULATION_NAME}_place_orphan (asection * s,
				   const char * secname,
				   int constraint)
{
  char * lower_name;
  char * upper_name;
  char * name;
  lang_output_section_statement_type * lower;
  lang_output_section_statement_type * upper;

  if ((s->flags & SEC_ALLOC) == 0)
    return NULL;

  if (bfd_link_relocatable (&link_info))
    return NULL;

  /* If constraints are involved let the linker handle the placement normally.  */
  if (constraint != 0)
    return NULL;

  if (strncmp (secname, ".upper.", 7) == 0
      || strncmp (secname, ".lower.", 7) == 0)
    {
      warn_no_output_section (secname);
      return NULL;
    }

  /* We only need special handling for .either sections.  */
  if (strncmp (secname, ".either.", 8) != 0)
    return NULL;

  /* Skip the .either prefix.  */
  secname += 7;

  /* Compute the names of the corresponding upper and lower
     sections.  If the input section name contains another period,
     only use the part of the name before the second dot.  */
  if (strchr (secname + 1, '.') != NULL)
    {
      name = xstrdup (secname);

      * strchr (name + 1, '.') = 0;
    }
  else
    name = (char *) secname;

  lower_name = concat (".lower", name, NULL);
  upper_name = concat (".upper", name, NULL);

  /* Find the corresponding lower and upper sections.  */
  lower = lang_output_section_find (lower_name);
  upper = lang_output_section_find (upper_name);

  if (lower == NULL && upper == NULL)
    {
      einfo (_("%P: error: no section named %s or %s in linker script\n"),
	     lower_name, upper_name);
      goto end;
    }
  else if (lower == NULL)
    {
      lower = lang_output_section_find (name);
      if (lower == NULL)
	{
	  einfo (_("%P: error: no section named %s in linker script\n"), name);
	  goto end;
	}
    }

  /* Always place orphaned sections in lower.  Optimal placement of either
     sections is performed later, once section sizes have been finalized.  */
  lang_add_section (& lower->children, s, NULL, NULL, lower);
 end:
  free (upper_name);
  free (lower_name);
  return lower;
}
EOF
fi

fragment <<EOF

static bool
change_output_section (lang_statement_union_type **head,
		       asection *s,
		       lang_output_section_statement_type *new_os,
		       lang_output_section_statement_type *old_os)
{
  asection *is;
  lang_statement_union_type * prev = NULL;
  lang_statement_union_type * curr;

  curr = *head;
  while (curr != NULL)
    {
      switch (curr->header.type)
	{
	case lang_input_section_enum:
	  is = curr->input_section.section;
	  if (is == s)
	    {
	      lang_statement_list_type *old_list
		= (lang_statement_list_type *) &old_os->children;
	      s->output_section = NULL;
	      lang_add_section (&new_os->children, s,
				curr->input_section.pattern, NULL, new_os);

	      /* Remove the section from the old output section.  */
	      if (prev == NULL)
		*head = curr->header.next;
	      else
		prev->header.next = curr->header.next;
	      /* If the input section we just moved is the tail of the old
		 output section, then we also need to adjust that tail.  */
	      if (old_list->tail == (lang_statement_union_type **) curr)
		old_list->tail = (lang_statement_union_type **) prev;

	      return true;
	    }
	  break;
	case lang_wild_statement_enum:
	  if (change_output_section (&(curr->wild_statement.children.head),
				     s, new_os, old_os))
	    return true;
	  break;
	default:
	  break;
	}
      prev = curr;
      curr = curr->header.next;
    }
  return false;
}

static void
add_region_prefix (bfd *abfd ATTRIBUTE_UNUSED, asection *s,
		   void *unused ATTRIBUTE_UNUSED)
{
  const char *curr_name = bfd_section_name (s);
  int region = REGION_NONE;

  if (strncmp (curr_name, ".text", 5) == 0)
    region = code_region;
  else if (strncmp (curr_name, ".data", 5) == 0)
    region = data_region;
  else if (strncmp (curr_name, ".bss", 4) == 0)
    region = data_region;
  else if (strncmp (curr_name, ".rodata", 7) == 0)
    region = data_region;
  else
    return;

  switch (region)
    {
    case REGION_NONE:
      break;
    case REGION_UPPER:
      bfd_rename_section (s, concat (".upper", curr_name, NULL));
      break;
    case REGION_LOWER:
      bfd_rename_section (s, concat (".lower", curr_name, NULL));
      break;
    case REGION_EITHER:
      bfd_rename_section (s, concat (".either", curr_name, NULL));
      break;
    default:
      /* Unreachable.  */
      FAIL ();
      break;
    }
}

static void
msp430_elf_after_open (void)
{
  bfd *abfd;

  gld${EMULATION_NAME}_after_open ();

  /* If neither --code-region or --data-region have been passed, do not
     transform sections names.  */
  if ((code_region == REGION_NONE && data_region == REGION_NONE)
      || disable_sec_transformation)
    return;

  for (abfd = link_info.input_bfds; abfd != NULL; abfd = abfd->link.next)
    bfd_map_over_sections (abfd, add_region_prefix, NULL);
}

#define OPTION_CODE_REGION		321
#define OPTION_DATA_REGION		(OPTION_CODE_REGION + 1)
#define OPTION_DISABLE_TRANS		(OPTION_CODE_REGION + 2)

static void
gld${EMULATION_NAME}_add_options
  (int ns, char **shortopts, int nl, struct option **longopts,
   int nrl ATTRIBUTE_UNUSED, struct option **really_longopts ATTRIBUTE_UNUSED)
{
  static const char xtra_short[] = { };

  static const struct option xtra_long[] =
    {
      { "code-region", required_argument, NULL, OPTION_CODE_REGION },
      { "data-region", required_argument, NULL, OPTION_DATA_REGION },
      { "disable-sec-transformation", no_argument, NULL,
	OPTION_DISABLE_TRANS },
      { NULL, no_argument, NULL, 0 }
    };

  *shortopts = (char *) xrealloc (*shortopts, ns + sizeof (xtra_short));
  memcpy (*shortopts + ns, &xtra_short, sizeof (xtra_short));
  *longopts = (struct option *)
    xrealloc (*longopts, nl * sizeof (struct option) + sizeof (xtra_long));
  memcpy (*longopts + nl, &xtra_long, sizeof (xtra_long));
}

static void
gld${EMULATION_NAME}_list_options (FILE * file)
{
  fprintf (file, _("  --code-region={either,lower,upper,none}\n\
        Transform .text* sections to {either,lower,upper,none}.text* sections\n"));
  fprintf (file, _("  --data-region={either,lower,upper,none}\n\
        Transform .data*, .rodata* and .bss* sections to\n\
        {either,lower,upper,none}.{bss,data,rodata}* sections\n"));
  fprintf (file, _("  --disable-sec-transformation\n\
        Disable transformation of .{text,data,bss,rodata}* sections to\n\
        add the {either,lower,upper,none} prefixes\n"));
}

static bool
gld${EMULATION_NAME}_handle_option (int optc)
{
  switch (optc)
    {
    case OPTION_CODE_REGION:
      if (strcmp (optarg, "upper") == 0)
	code_region = REGION_UPPER;
      else if (strcmp (optarg, "lower") == 0)
	code_region = REGION_LOWER;
      else if (strcmp (optarg, "either") == 0)
	code_region = REGION_EITHER;
      else if (strcmp (optarg, "none") == 0)
	code_region = REGION_NONE;
      else if (strlen (optarg) == 0)
	{
	  einfo (_("%P: --code-region requires an argument: "
		   "{upper,lower,either,none}\n"));
	  return false;
	}
      else
	{
	  einfo (_("%P: error: unrecognized argument to --code-region= option: "
		   "\"%s\"\n"), optarg);
	  return false;
	}
      break;

    case OPTION_DATA_REGION:
      if (strcmp (optarg, "upper") == 0)
	data_region = REGION_UPPER;
      else if (strcmp (optarg, "lower") == 0)
	data_region = REGION_LOWER;
      else if (strcmp (optarg, "either") == 0)
	data_region = REGION_EITHER;
      else if (strcmp (optarg, "none") == 0)
	data_region = REGION_NONE;
      else if (strlen (optarg) == 0)
	{
	  einfo (_("%P: --data-region requires an argument: "
		   "{upper,lower,either,none}\n"));
	  return false;
	}
      else
	{
	  einfo (_("%P: error: unrecognized argument to --data-region= option: "
		   "\"%s\"\n"), optarg);
	  return false;
	}
      break;

    case OPTION_DISABLE_TRANS:
      disable_sec_transformation = true;
      break;

    default:
      return false;
    }
  return true;
}

static void
eval_upper_either_sections (bfd *abfd ATTRIBUTE_UNUSED,
			    asection *s, void *data)
{
  const char * base_sec_name;
  const char * curr_name;
  char * either_name;
  int curr_region;

  lang_output_section_statement_type * lower;
  lang_output_section_statement_type * upper;
  static bfd_size_type *lower_size = 0;
  static bfd_size_type *upper_size = 0;
  static bfd_size_type lower_size_rom = 0;
  static bfd_size_type lower_size_ram = 0;
  static bfd_size_type upper_size_rom = 0;
  static bfd_size_type upper_size_ram = 0;

  if ((s->flags & SEC_ALLOC) == 0)
    return;
  if (bfd_link_relocatable (&link_info))
    return;

  base_sec_name = (const char *) data;
  curr_name = bfd_section_name (s);

  /* Only concerned with .either input sections in the upper output section.  */
  either_name = concat (".either", base_sec_name, NULL);
  if (strncmp (curr_name, either_name, strlen (either_name)) != 0
      || strncmp (s->output_section->name, ".upper", 6) != 0)
    goto end;

  lower = lang_output_section_find (concat (".lower", base_sec_name, NULL));
  upper = lang_output_section_find (concat (".upper", base_sec_name, NULL));

  if (upper == NULL || upper->region == NULL)
    goto end;
  else if (lower == NULL)
    lower = lang_output_section_find (base_sec_name);
  if (lower == NULL || lower->region == NULL)
    goto end;

  if (strcmp (base_sec_name, ".text") == 0
      || strcmp (base_sec_name, ".rodata") == 0)
    curr_region = ROM;
  else
    curr_region = RAM;

  if (curr_region == ROM)
    {
      if (lower_size_rom == 0)
	{
	  lower_size_rom = lower->region->current - lower->region->origin;
	  upper_size_rom = upper->region->current - upper->region->origin;
	}
      lower_size = &lower_size_rom;
      upper_size = &upper_size_rom;
    }
  else if (curr_region == RAM)
    {
      if (lower_size_ram == 0)
	{
	  lower_size_ram = lower->region->current - lower->region->origin;
	  upper_size_ram = upper->region->current - upper->region->origin;
	}
      lower_size = &lower_size_ram;
      upper_size = &upper_size_ram;
    }

  /* If the upper region is overflowing, try moving sections to the lower
     region.
     Note that there isn't any general benefit to using lower memory over upper
     memory, so we only move sections around with the goal of making the program
     fit.  */
  if (*upper_size > upper->region->length
      && *lower_size + s->size < lower->region->length)
    {
      if (change_output_section (&(upper->children.head), s, lower, upper))
	{
	  *upper_size -= s->size;
	  *lower_size += s->size;
	}
    }
 end:
  free (either_name);
}

static void
eval_lower_either_sections (bfd *abfd ATTRIBUTE_UNUSED,
			    asection *s, void *data)
{
  const char * base_sec_name;
  const char * curr_name;
  char * either_name;
  int curr_region;
  lang_output_section_statement_type * output_sec;
  lang_output_section_statement_type * lower;
  lang_output_section_statement_type * upper;

  static bfd_size_type *lower_size = 0;
  static bfd_size_type lower_size_rom = 0;
  static bfd_size_type lower_size_ram = 0;

  if ((s->flags & SEC_ALLOC) == 0)
    return;
  if (bfd_link_relocatable (&link_info))
    return;

  base_sec_name = (const char *) data;
  curr_name = bfd_section_name (s);

  /* Only concerned with .either input sections in the lower or "default"
     output section i.e. not in the upper output section.  */
  either_name = concat (".either", base_sec_name, NULL);
  if (strncmp (curr_name, either_name, strlen (either_name)) != 0
      || strncmp (s->output_section->name, ".upper", 6) == 0)
    return;

  if (strcmp (base_sec_name, ".text") == 0
      || strcmp (base_sec_name, ".rodata") == 0)
    curr_region = ROM;
  else
    curr_region = RAM;

  output_sec = lang_output_section_find (s->output_section->name);

  /* If the output_section doesn't exist, this has already been reported in
     place_orphan, so don't need to warn again.  */
  if (output_sec == NULL || output_sec->region == NULL)
    goto end;

  /* lower and output_sec might be the same, but in some cases an .either
     section can end up in base_sec_name if it hasn't been placed by
     place_orphan.  */
  lower = lang_output_section_find (concat (".lower", base_sec_name, NULL));
  upper = lang_output_section_find (concat (".upper", base_sec_name, NULL));
  if (upper == NULL)
    goto end;

  if (curr_region == ROM)
    {
      if (lower_size_rom == 0)
	{
	  /* Get the size of other items in the lower region that aren't the
	     sections to be moved around.  */
	  lower_size_rom
	    = (output_sec->region->current - output_sec->region->origin)
	    - scan_children (output_sec->children.head);
	  if (output_sec != lower && lower != NULL)
	    lower_size_rom -= scan_children (lower->children.head);
	}
      lower_size = &lower_size_rom;
    }
  else if (curr_region == RAM)
    {
      if (lower_size_ram == 0)
	{
	  lower_size_ram
	    = (output_sec->region->current - output_sec->region->origin)
	    - scan_children (output_sec->children.head);
	  if (output_sec != lower && lower != NULL)
	    lower_size_ram -= scan_children (lower->children.head);
	}
      lower_size = &lower_size_ram;
    }
  /* Move sections that cause the lower region to overflow to the upper region.  */
  if (*lower_size + s->size > output_sec->region->length)
    change_output_section (&(output_sec->children.head), s, upper, output_sec);
  else
    *lower_size += s->size;
 end:
  free (either_name);
}

/* This function is similar to lang_relax_sections, but without the size
   evaluation code that is always executed after relaxation.  */
static void
intermediate_relax_sections (void)
{
  int i = link_info.relax_pass;

  /* The backend can use it to determine the current pass.  */
  link_info.relax_pass = 0;

  while (i--)
    {
      bool relax_again;

      link_info.relax_trip = -1;
      do
	{
	  link_info.relax_trip++;

	  lang_do_assignments (lang_assigning_phase_enum);

	  lang_reset_memory_regions ();

	  relax_again = false;
	  lang_size_sections (&relax_again, false);
	}
      while (relax_again);

      link_info.relax_pass++;
    }
}

static void
msp430_elf_after_allocation (void)
{
  int relax_count = 0;
  unsigned int i;
  /* Go over each section twice, once to place either sections that don't fit
     in lower into upper, and then again to move any sections in upper that
     fit in lower into lower.  */
  for (i = 0; i < 8; i++)
    {
      int placement_stage = (i < 4) ? LOWER_TO_UPPER : UPPER_TO_LOWER;
      const char * base_sec_name;
      lang_output_section_statement_type * upper;

      switch (i % 4)
	{
	default:
	case 0:
	  base_sec_name = ".text";
	  break;
	case 1:
	  base_sec_name = ".data";
	  break;
	case 2:
	  base_sec_name = ".bss";
	  break;
	case 3:
	  base_sec_name = ".rodata";
	  break;
	}
      upper = lang_output_section_find (concat (".upper", base_sec_name, NULL));
      if (upper != NULL)
	{
	  /* Can't just use one iteration over the all the sections to make
	     both lower->upper and upper->lower transformations because the
	     iterator encounters upper sections before all lower sections have
	     been examined.  */
	  bfd *abfd;

	  if (placement_stage == LOWER_TO_UPPER)
	    {
	      /* Perform relaxation and get the final size of sections
		 before trying to fit .either sections in the correct
		 ouput sections.  */
	      if (relax_count == 0)
		{
		  intermediate_relax_sections ();
		  relax_count++;
		}
	      for (abfd = link_info.input_bfds; abfd != NULL;
		   abfd = abfd->link.next)
		{
		  bfd_map_over_sections (abfd, eval_lower_either_sections,
					 (void *) base_sec_name);
		}
	    }
	  else if (placement_stage == UPPER_TO_LOWER)
	    {
	      /* Relax again before moving upper->lower.  */
	      if (relax_count == 1)
		{
		  intermediate_relax_sections ();
		  relax_count++;
		}
	      for (abfd = link_info.input_bfds; abfd != NULL;
		   abfd = abfd->link.next)
		{
		  bfd_map_over_sections (abfd, eval_upper_either_sections,
					 (void *) base_sec_name);
		}
	    }

	}
    }
  gld${EMULATION_NAME}_after_allocation ();
}

/* Return TRUE if a non-debug input section in L has positive size and matches
   the given name.  */
static int
input_section_exists (lang_statement_union_type * l, const char * name)
{
  while (l != NULL)
    {
      switch (l->header.type)
	{
	case lang_input_section_enum:
	  if ((l->input_section.section->flags & SEC_ALLOC)
	      && l->input_section.section->size > 0
	      && !strcmp (l->input_section.section->name, name))
	    return true;
	  break;

	case lang_wild_statement_enum:
	  if (input_section_exists (l->wild_statement.children.head, name))
	    return true;
	  break;

	default:
	  break;
	}
      l = l->header.next;
    }
  return false;
}

/* Some MSP430 linker scripts do not include ALIGN directives to ensure
   __preinit_array_start, __init_array_start or __fini_array_start are word
   aligned.
   If __*_array_start symbols are not word aligned, the code in crt0 to run
   through the array and call the functions will crash.
   To avoid warning unnecessarily when the .*_array sections are not being
   used for running constructors/destructors, only emit the warning if
   the associated section exists and has size.  */
static void
check_array_section_alignment (void)
{
  int i;
  lang_output_section_statement_type * rodata_sec;
  lang_output_section_statement_type * rodata2_sec;
  const char * array_names[3][2] = { { ".init_array", "__init_array_start" },
	{ ".preinit_array", "__preinit_array_start" },
	{ ".fini_array", "__fini_array_start" } };

  /* .{preinit,init,fini}_array could be in either .rodata or .rodata2.  */
  rodata_sec = lang_output_section_find (".rodata");
  rodata2_sec = lang_output_section_find (".rodata2");
  if (rodata_sec == NULL && rodata2_sec == NULL)
    return;

  /* There are 3 .*_array sections which must be checked for alignment.  */
  for (i = 0; i < 3; i++)
    {
      struct bfd_link_hash_entry * sym;
      if (((rodata_sec && input_section_exists (rodata_sec->children.head,
						array_names[i][0]))
	   || (rodata2_sec && input_section_exists (rodata2_sec->children.head,
						    array_names[i][0])))
	  && (sym = bfd_link_hash_lookup (link_info.hash, array_names[i][1],
					  false, false, true))
	  && sym->type == bfd_link_hash_defined
	  && sym->u.def.value % 2)
	{
	  einfo ("%P: warning: \"%s\" symbol (%pU) is not word aligned\n",
		 array_names[i][1], NULL);
	}
    }
}

static void
gld${EMULATION_NAME}_finish (void)
{
  finish_default ();
  check_array_section_alignment ();
}
EOF

LDEMUL_AFTER_OPEN=msp430_elf_after_open
LDEMUL_AFTER_ALLOCATION=msp430_elf_after_allocation
LDEMUL_PLACE_ORPHAN=${LDEMUL_PLACE_ORPHAN-gld${EMULATION_NAME}_place_orphan}
LDEMUL_FINISH=gld${EMULATION_NAME}_finish
LDEMUL_ADD_OPTIONS=gld${EMULATION_NAME}_add_options
LDEMUL_HANDLE_OPTION=gld${EMULATION_NAME}_handle_option
LDEMUL_LIST_OPTIONS=gld${EMULATION_NAME}_list_options

source_em ${srcdir}/emultempl/emulation.em
# 
# Local Variables:
# mode: c
# End:
